// SPDX-License-Identifier: AGPL-3.0-only

package pihole

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/LordHorkos/scamwall/internal/audit"
)

// authResponse mirrors the documented session envelope.
//
// SID and CSRF are pointers so they can be cleared immediately after use.
type sessionEnvelope struct {
	Valid    bool    `json:"valid"`
	TOTP     bool    `json:"totp"`
	SID      *string `json:"sid"`
	CSRF     *string `json:"csrf"`
	Validity int     `json:"validity"`
	Message  *string `json:"message"`
}

func (s sessionEnvelope) state() SessionState {
	st := SessionState{Valid: s.Valid, TOTP: s.TOTP, Validity: s.Validity}
	if s.Message != nil {
		st.Message = sanitizeMessage(*s.Message)
	}
	return st
}

type authResponse struct {
	Session sessionEnvelope `json:"session"`
	Took    float64         `json:"took"`
}

// apiErrorEnvelope mirrors Pi-hole's error shape.
type apiErrorEnvelope struct {
	Error struct {
		Key     string  `json:"key"`
		Message string  `json:"message"`
		Hint    *string `json:"hint"`
	} `json:"error"`
	Took float64 `json:"took"`
}

type localRemote struct {
	Local struct {
		Branch  *string `json:"branch"`
		Version *string `json:"version"`
		Hash    *string `json:"hash"`
		Date    *string `json:"date"`
	} `json:"local"`
	Remote struct {
		Version *string `json:"version"`
		Hash    *string `json:"hash"`
	} `json:"remote"`
}

func (lr localRemote) component() ComponentVersion {
	return ComponentVersion{
		LocalBranch:   deref(lr.Local.Branch),
		LocalVersion:  deref(lr.Local.Version),
		LocalHash:     deref(lr.Local.Hash),
		LocalDate:     deref(lr.Local.Date),
		RemoteVersion: deref(lr.Remote.Version),
		RemoteHash:    deref(lr.Remote.Hash),
	}
}

type versionResponse struct {
	Version struct {
		Core localRemote `json:"core"`
		Web  localRemote `json:"web"`
		FTL  localRemote `json:"ftl"`
	} `json:"version"`
	Took float64 `json:"took"`
}

func (v versionResponse) toVersionInfo() *VersionInfo {
	return &VersionInfo{
		Core: v.Version.Core.component(),
		Web:  v.Version.Web.component(),
		FTL:  v.Version.FTL.component(),
	}
}

// deref returns the value of a nullable string field. Every version field in
// the Pi-hole schema is nullable, so this avoids a nil dereference on a
// perfectly valid response.
func deref(p *string) string {
	if p == nil {
		return ""
	}
	return sanitizeMessage(*p)
}

// do performs one API call, with bounded retries when the request is safe.
//
// retryable must be true only for idempotent, side-effect-free requests.
func (c *Client) do(ctx context.Context, method, path string, body []byte, out any, retryable bool) error {
	endpoint := c.cfg.BaseURL() + path

	u, err := url.Parse(endpoint)
	if err != nil {
		return fmt.Errorf("invalid endpoint %s", path)
	}
	// Plaintext is refused here as well as in configuration. A single check is
	// a single place to get wrong.
	if u.Scheme != "https" {
		return fmt.Errorf("%w: %s", ErrPlaintextRefused, u.Scheme)
	}
	// The session id must never appear in a URL: query strings are recorded by
	// proxies, access logs, and browser history. Pi-hole offers a `sid` query
	// parameter; ScamWall does not use it.
	if u.RawQuery != "" {
		return errors.New("query parameters are not used by this client")
	}

	attempts := 1
	if retryable {
		attempts += c.cfg.Pihole.MaxRetries
	}

	var lastErr error
	for attempt := range attempts {
		if attempt > 0 {
			delay := jitteredBackoff(c.cfg.Pihole.RetryBaseDelay.D(), attempt-1)
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(delay):
			}
		}

		err := c.attempt(ctx, method, u.String(), path, body, out)
		if err == nil {
			return nil
		}
		lastErr = err

		// Context errors are terminal: the caller asked us to stop.
		if ctx.Err() != nil {
			return err
		}
		if !retryable || !isRetryable(err) {
			return err
		}
		c.log.Warn("pihole.retry",
			audit.F("endpoint", path),
			audit.F("attempt", attempt+1),
			audit.F("of", attempts))
	}
	return lastErr
}

// isRetryable reports whether an error is worth another attempt.
//
// Authentication and authorisation failures are never retried: they will not
// succeed on repetition, and repeating them can trip rate limits or lockouts.
func isRetryable(err error) bool {
	var apiErr *APIError
	if errors.As(err, &apiErr) {
		switch apiErr.Status {
		case http.StatusTooManyRequests,
			http.StatusInternalServerError,
			http.StatusBadGateway,
			http.StatusServiceUnavailable,
			http.StatusGatewayTimeout:
			return true
		default:
			return false
		}
	}
	// A response that was too large, or of the wrong type, indicates the peer
	// is not behaving as documented. Retrying will not change that.
	if errors.Is(err, ErrResponseTooLarge) ||
		errors.Is(err, ErrUnexpectedContent) ||
		errors.Is(err, ErrCrossOriginRedirect) ||
		errors.Is(err, ErrTooManyRedirects) ||
		errors.Is(err, ErrUnexpectedDial) {
		return false
	}
	// Remaining failures are transport-level (dial, TLS, timeout). TLS
	// failures are not distinguished here because retrying a handshake against
	// a correctly-configured peer is harmless and a misconfigured peer fails
	// the same way every time.
	return true
}

func (c *Client) attempt(ctx context.Context, method, fullURL, path string, body []byte, out any) error {
	reqCtx, cancel := context.WithTimeout(ctx, c.cfg.Pihole.RequestTimeout.D())
	defer cancel()

	var reader io.Reader
	if body != nil {
		reader = bytes.NewReader(body)
	}

	req, err := http.NewRequestWithContext(reqCtx, method, fullURL, reader)
	if err != nil {
		return fmt.Errorf("build request for %s", path)
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", UserAgent)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	// The session id travels only in this header, and only when one is held.
	c.mu.Lock()
	if !c.sid.IsZero() {
		req.Header.Set("X-FTL-SID", c.sid.Reveal())
	}
	c.mu.Unlock()

	resp, err := c.http.Do(req)
	if err != nil {
		// net/url wraps transport errors in *url.Error, whose message contains
		// the full URL. That is safe here because the URL never carries
		// credentials, but the error is still rewritten so that nothing
		// unexpected from a lower layer reaches a log.
		return redactTransportError(path, err)
	}
	defer func() {
		// Drain a bounded amount so the connection can be reused, then close.
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
		_ = resp.Body.Close()
	}()

	// 204 carries no body. This is the documented success response for logout.
	if resp.StatusCode == http.StatusNoContent {
		return nil
	}

	ct := resp.Header.Get("Content-Type")
	if !mediaTypeIsJSON(ct) {
		// The received content type is reported because it is a protocol fact,
		// not user data, and it is the single most useful clue when something
		// other than Pi-hole answers on the port.
		return fmt.Errorf("%w: %s returned %q", ErrUnexpectedContent, path, sanitizeMessage(ct))
	}

	limit := c.cfg.Pihole.MaxResponseBytes
	payload, err := io.ReadAll(io.LimitReader(resp.Body, limit+1))
	if err != nil {
		return fmt.Errorf("read response from %s: %w", path, redactTransportError(path, err))
	}
	if int64(len(payload)) > limit {
		return fmt.Errorf("%w: %s exceeded %d bytes", ErrResponseTooLarge, path, limit)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return newAPIError(resp.StatusCode, path, payload)
	}

	if out == nil {
		return nil
	}
	dec := json.NewDecoder(bytes.NewReader(payload))
	if err := dec.Decode(out); err != nil {
		// The body is never included: it is the thing most likely to contain
		// something sensitive if the peer is not what we expect.
		return fmt.Errorf("decode response from %s: malformed JSON", path)
	}
	return nil
}

// newAPIError builds a redacted error from a failure response.
func newAPIError(status int, path string, payload []byte) error {
	e := &APIError{Status: status, Endpoint: path}
	var env apiErrorEnvelope
	if err := json.Unmarshal(payload, &env); err == nil {
		e.Key = sanitizeMessage(env.Error.Key)
		e.Message = sanitizeMessage(env.Error.Message)
	}
	return e
}

// redactTransportError rewrites a transport error so that only its class and
// the endpoint path survive.
func redactTransportError(path string, err error) error {
	switch {
	case errors.Is(err, context.DeadlineExceeded):
		return fmt.Errorf("request to %s timed out: %w", path, context.DeadlineExceeded)
	case errors.Is(err, context.Canceled):
		return fmt.Errorf("request to %s cancelled: %w", path, context.Canceled)
	case errors.Is(err, ErrCrossOriginRedirect):
		return fmt.Errorf("request to %s: %w", path, ErrCrossOriginRedirect)
	case errors.Is(err, ErrTooManyRedirects):
		return fmt.Errorf("request to %s: %w", path, ErrTooManyRedirects)
	case errors.Is(err, ErrUnexpectedDial):
		return fmt.Errorf("request to %s: %w", path, ErrUnexpectedDial)
	}

	msg := err.Error()
	switch {
	case strings.Contains(msg, "x509:") || strings.Contains(msg, "tls:") || strings.Contains(msg, "certificate"):
		// The specific verification failure is preserved because it is exactly
		// what an operator needs, and it contains no credential. It is
		// sanitised and bounded like any other peer-influenced string.
		return fmt.Errorf("TLS verification failed for %s: %s", path, sanitizeMessage(stripURL(msg)))
	default:
		return fmt.Errorf("transport error for %s: %s", path, sanitizeMessage(stripURL(msg)))
	}
}

// stripURL removes the leading `Method "URL": ` prefix that *url.Error adds.
func stripURL(msg string) string {
	if i := strings.Index(msg, `": `); i >= 0 && strings.Contains(msg[:i], `"`) {
		return msg[i+3:]
	}
	return msg
}
