// SPDX-License-Identifier: AGPL-3.0-only

// Package pihole is a read-only client for the Pi-hole v6 HTTPS API.
//
// The package exposes no method that mutates Pi-hole state. The only non-GET
// requests it can issue are POST /api/auth and DELETE /api/auth, which create
// and destroy ScamWall's own session and change nothing else.
package pihole

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"math/rand/v2"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/LordHorkos/scamwall/internal/audit"
	"github.com/LordHorkos/scamwall/internal/config"
)

// UserAgent identifies ScamWall to Pi-hole. It carries no host or user detail.
const UserAgent = "ScamWall/0.1 (+https://github.com/LordHorkos/scamwall)"

// MaxCABytes bounds reads of the CA file.
const MaxCABytes = 512 * 1024

// maxRedirects caps same-origin redirect following.
const maxRedirects = 3

// Endpoints used by this client. Declared as constants so that the complete
// set of reachable endpoints is visible in one place and can be asserted by a
// test.
const (
	epAuth    = "/api/auth"
	epVersion = "/api/info/version"
)

// Errors returned by the client.
var (
	ErrPlaintextRefused   = errors.New("plaintext HTTP is refused")
	ErrCrossOriginRedirect = errors.New("refused redirect to a different origin")
	ErrTooManyRedirects   = errors.New("too many redirects")
	ErrResponseTooLarge   = errors.New("response exceeds maximum size")
	ErrUnexpectedContent  = errors.New("unexpected response content type")
	ErrNotAuthenticated   = errors.New("no active session")
	ErrNoSessionID        = errors.New("authentication succeeded but returned no session id")
	ErrUnexpectedDial     = errors.New("refused connection to an unexpected address")
	ErrCAInvalid          = errors.New("certificate authority file contains no usable certificate")
)

// APIError is a redacted representation of a failed API response.
//
// It carries the status, the endpoint, and Pi-hole's own error key. It never
// carries a request body, a response body, a header, or a credential.
type APIError struct {
	Status   int
	Endpoint string
	Key      string
	Message  string
}

func (e *APIError) Error() string {
	b := strings.Builder{}
	fmt.Fprintf(&b, "pi-hole api: %s returned %d", e.Endpoint, e.Status)
	if e.Key != "" {
		fmt.Fprintf(&b, " (%s)", e.Key)
	}
	if e.Message != "" {
		fmt.Fprintf(&b, ": %s", e.Message)
	}
	return b.String()
}

// Unauthorized reports whether the failure was an authentication failure.
func (e *APIError) Unauthorized() bool { return e.Status == http.StatusUnauthorized }

// Forbidden reports whether the failure was an authorisation failure.
func (e *APIError) Forbidden() bool { return e.Status == http.StatusForbidden }

// RateLimited reports whether Pi-hole asked us to slow down.
func (e *APIError) RateLimited() bool { return e.Status == http.StatusTooManyRequests }

// SessionState is the non-sensitive part of a Pi-hole session response.
//
// The session id and CSRF token are deliberately absent from this type. The
// session id is held privately by the Client and the CSRF token is discarded,
// so neither can reach a caller, a log, or a report.
type SessionState struct {
	Valid    bool
	TOTP     bool
	Validity int
	Message  string
}

// ComponentVersion is the local and remote version of one Pi-hole component.
type ComponentVersion struct {
	LocalBranch  string
	LocalVersion string
	LocalHash    string
	LocalDate    string
	RemoteVersion string
	RemoteHash    string
}

// VersionInfo is the non-sensitive version report from /api/info/version.
type VersionInfo struct {
	Core ComponentVersion
	Web  ComponentVersion
	FTL  ComponentVersion
}

// Client is a read-only Pi-hole API client.
type Client struct {
	cfg  config.Config
	log  *audit.Logger
	http *http.Client

	mu  sync.Mutex
	sid config.Secret
}

// New builds a client with TLS pinned to the configured private CA.
func New(cfg config.Config, log *audit.Logger) (*Client, error) {
	tlsCfg, err := buildTLSConfig(cfg)
	if err != nil {
		return nil, err
	}

	expected := net.JoinHostPort(cfg.Pihole.Host, itoa(cfg.Pihole.Port))
	dialAddr := cfg.DialAddress()
	dialer := &net.Dialer{Timeout: cfg.Pihole.ConnectTimeout.D()}

	transport := &http.Transport{
		TLSClientConfig:       tlsCfg,
		TLSHandshakeTimeout:   cfg.Pihole.ConnectTimeout.D(),
		ResponseHeaderTimeout: cfg.Pihole.RequestTimeout.D(),
		ExpectContinueTimeout: time.Second,
		IdleConnTimeout:       30 * time.Second,
		MaxIdleConns:          2,
		MaxIdleConnsPerHost:   2,
		ForceAttemptHTTP2:     true,
		// Proxies are ignored. A proxy would terminate or observe the
		// connection to a service that is, by definition, on the local host.
		Proxy: nil,
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			// Only the configured origin may be dialled. Combined with the
			// redirect policy, this means no response can steer the client at
			// another host.
			if addr != expected {
				return nil, fmt.Errorf("%w: %s", ErrUnexpectedDial, addr)
			}
			// Resolution is overridden here, and only here. Certificate and
			// hostname verification are unaffected: tls.Config.ServerName
			// still requires a certificate valid for the configured host.
			return dialer.DialContext(ctx, network, dialAddr)
		},
	}

	c := &Client{
		cfg: cfg,
		log: log,
		http: &http.Client{
			Transport: transport,
			Timeout:   cfg.Pihole.TotalTimeout.D(),
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				if len(via) >= maxRedirects {
					return ErrTooManyRedirects
				}
				origin := via[0].URL
				if req.URL.Scheme != origin.Scheme || req.URL.Host != origin.Host {
					return fmt.Errorf("%w: %s -> %s", ErrCrossOriginRedirect, origin.Host, req.URL.Host)
				}
				return nil
			},
		},
	}
	return c, nil
}

// buildTLSConfig creates a TLS configuration trusting only the configured CA.
//
// The system trust store is not consulted. Pi-hole's certificate is issued by a
// private CA, so accepting any publicly-trusted issuer would widen the set of
// parties able to impersonate it to every CA on the internet.
func buildTLSConfig(cfg config.Config) (*tls.Config, error) {
	f, err := os.Open(cfg.Pihole.CAPath)
	if err != nil {
		return nil, fmt.Errorf("open CA: %w", err)
	}
	defer func() { _ = f.Close() }()

	pem, err := io.ReadAll(io.LimitReader(f, MaxCABytes+1))
	if err != nil {
		return nil, fmt.Errorf("read CA: %w", err)
	}
	if len(pem) > MaxCABytes {
		return nil, fmt.Errorf("CA file exceeds %d bytes", MaxCABytes)
	}

	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(pem) {
		return nil, fmt.Errorf("%w: %s", ErrCAInvalid, cfg.Pihole.CAPath)
	}

	return &tls.Config{
		RootCAs:    pool,
		ServerName: cfg.Pihole.Host,
		MinVersion: tls.VersionTLS12,
		// InsecureSkipVerify is intentionally left at its zero value (false).
		// There is no configuration path that can set it, and a test asserts
		// the identifier does not appear in this package.
	}, nil
}

// SessionActive reports whether a session id is held.
func (c *Client) SessionActive() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return !c.sid.IsZero()
}

// Login authenticates and stores the session id in memory.
//
// The session id is never written to disk, never placed in a URL, and never
// logged. The CSRF token returned alongside it is discarded: ScamWall
// authenticates with a header rather than a cookie, so CSRF does not apply.
func (c *Client) Login(ctx context.Context, secret config.Secret) (SessionState, error) {
	if secret.IsZero() {
		return SessionState{}, errors.New("cannot authenticate with an empty password")
	}

	// One of exactly two sanctioned Reveal call sites (the other sets the
	// X-FTL-SID header). Both are the moment a credential goes on the wire.
	body, err := json.Marshal(struct {
		Password string `json:"password"`
	}{Password: secret.Reveal()})
	if err != nil {
		return SessionState{}, errors.New("failed to encode authentication request")
	}
	// Best-effort reduction of the plaintext's lifetime in memory. Go strings
	// are immutable, so the copy created by Reveal cannot be wiped; this
	// narrows the window without eliminating it.
	defer func() {
		for i := range body {
			body[i] = 0
		}
	}()

	var resp authResponse
	// Authentication is never retried. Pi-hole rate-limits login and returns
	// 429 when its session table is full, so a retry storm could lock out a
	// legitimate operator during an incident.
	err = c.do(ctx, http.MethodPost, epAuth, body, &resp, false)
	if err != nil {
		return SessionState{}, err
	}
	if resp.Session.SID == nil || *resp.Session.SID == "" {
		return SessionState{}, ErrNoSessionID
	}

	c.mu.Lock()
	c.sid = config.NewSecretString(*resp.Session.SID)
	c.mu.Unlock()

	// Overwrite the decoded copies so the only retained instance is the
	// redacting Secret.
	*resp.Session.SID = ""
	resp.Session.SID = nil
	resp.Session.CSRF = nil

	state := resp.Session.state()
	c.log.Info("pihole.login", audit.F("valid", state.Valid), audit.F("validity_seconds", state.Validity), audit.F("totp_enabled", state.TOTP))
	return state, nil
}

// Logout destroys the session.
//
// It runs under its own bounded context derived from ctx but detached from its
// cancellation, so a cancelled or failed operation still gets a real
// opportunity to tear down the session. Leaving a session behind is not
// harmless: it stays valid for its remaining lifetime and consumes one of a
// finite number of session seats.
func (c *Client) Logout(ctx context.Context) error {
	c.mu.Lock()
	active := !c.sid.IsZero()
	c.mu.Unlock()
	if !active {
		return nil
	}

	logoutCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), c.cfg.Pihole.LogoutTimeout.D())
	defer cancel()

	err := c.do(logoutCtx, http.MethodDelete, epAuth, nil, nil, false)

	// The session id is discarded regardless of the outcome. Retaining an id
	// that may already be invalid serves no purpose and only extends the time
	// a credential sits in memory.
	c.mu.Lock()
	c.sid.Destroy()
	c.mu.Unlock()

	var apiErr *APIError
	// 404 means the session is already gone, which is the desired end state.
	if errors.As(err, &apiErr) && apiErr.Status == http.StatusNotFound {
		c.log.Info("pihole.logout", audit.F("result", "no_session"))
		return nil
	}
	if err != nil {
		c.log.Error("pihole.logout_failed", err)
		return err
	}
	c.log.Info("pihole.logout", audit.F("result", "ok"))
	return nil
}

// ProbeAuth queries session state without sending a credential.
//
// Used by doctor to distinguish "cannot reach Pi-hole" from "can reach it but
// needs a password", without transmitting anything sensitive.
func (c *Client) ProbeAuth(ctx context.Context) (SessionState, error) {
	var resp authResponse
	err := c.do(ctx, http.MethodGet, epAuth, nil, &resp, true)
	if err != nil {
		var apiErr *APIError
		if errors.As(err, &apiErr) && apiErr.Unauthorized() {
			// 401 here is a successful probe: it proves the API is reachable,
			// speaks JSON, and requires authentication.
			return SessionState{Valid: false, Message: "authentication required"}, nil
		}
		return SessionState{}, err
	}
	resp.Session.SID = nil
	resp.Session.CSRF = nil
	return resp.Session.state(), nil
}

// Version reads Pi-hole component versions. Requires an active session.
func (c *Client) Version(ctx context.Context) (*VersionInfo, error) {
	if !c.SessionActive() {
		return nil, ErrNotAuthenticated
	}
	var resp versionResponse
	if err := c.do(ctx, http.MethodGet, epVersion, nil, &resp, true); err != nil {
		return nil, err
	}
	v := resp.toVersionInfo()
	c.log.Info("pihole.version_read",
		audit.F("core", v.Core.LocalVersion),
		audit.F("web", v.Web.LocalVersion),
		audit.F("ftl", v.FTL.LocalVersion))
	return v, nil
}

// WithSession authenticates, runs fn, and always attempts logout.
//
// Callers should prefer this over calling Login and Logout directly, because
// it makes the logout unconditional rather than dependent on every return path
// remembering to perform it.
func (c *Client) WithSession(ctx context.Context, secret config.Secret, fn func(context.Context) error) error {
	if _, err := c.Login(ctx, secret); err != nil {
		return err
	}
	defer func() {
		if err := c.Logout(ctx); err != nil {
			// Logout failure must not mask the caller's error, so it is logged
			// rather than returned.
			c.log.Warn("pihole.logout_incomplete", audit.F("reason", "see previous error"))
		}
	}()
	return fn(ctx)
}

func itoa(n int) string { return fmt.Sprintf("%d", n) }

// sanitizeMessage bounds and cleans a server-supplied message before it is
// allowed into an error string.
//
// Pi-hole's messages are short and generic, but they originate outside this
// process, so they are treated as untrusted: control characters are stripped
// and the length is capped to keep them out of logs as anything other than a
// short diagnostic.
func sanitizeMessage(s string) string {
	const maxLen = 200
	var b strings.Builder
	for _, r := range s {
		if r < 0x20 || r == 0x7f {
			continue
		}
		if b.Len() >= maxLen {
			break
		}
		b.WriteRune(r)
	}
	return strings.TrimSpace(b.String())
}

// jitteredBackoff returns a bounded, randomised delay for attempt n.
//
// Jitter prevents several ScamWall instances, or repeated retries after a
// shared outage, from synchronising into a thundering herd against a service
// whose availability is load-bearing for the whole network.
func jitteredBackoff(base time.Duration, attempt int) time.Duration {
	if base <= 0 {
		return 0
	}
	d := base << attempt
	const maxDelay = 5 * time.Second
	if d > maxDelay {
		d = maxDelay
	}
	// Full jitter: uniform in [0, d].
	return time.Duration(rand.Int64N(int64(d) + 1))
}

func mediaTypeIsJSON(ct string) bool {
	if ct == "" {
		return false
	}
	mt, _, err := mime.ParseMediaType(ct)
	if err != nil {
		return false
	}
	return mt == "application/json"
}
