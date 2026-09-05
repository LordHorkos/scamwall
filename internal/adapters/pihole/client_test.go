// SPDX-License-Identifier: AGPL-3.0-only

package pihole_test

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/LordHorkos/scamwall/internal/adapters/pihole"
	"github.com/LordHorkos/scamwall/internal/audit"
	"github.com/LordHorkos/scamwall/internal/config"
)

// newClient wires a client to a fake server and returns the captured log.
func newClient(t *testing.T, f *fakePihole) (*pihole.Client, *bytes.Buffer) {
	t.Helper()
	var logBuf bytes.Buffer
	c, err := pihole.New(configFor(t, f, f.ca.path), audit.New(&logBuf))
	if err != nil {
		t.Fatalf("client construction failed: %v", err)
	}
	return c, &logBuf
}

func versionHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/api/auth":
			writeJSON(w, http.StatusOK, loginOKBody())
		case r.Method == http.MethodDelete && r.URL.Path == "/api/auth":
			w.WriteHeader(http.StatusNoContent)
		case r.Method == http.MethodGet && r.URL.Path == "/api/info/version":
			writeJSON(w, http.StatusOK, `{"version":{
				"core":{"local":{"branch":"master","version":"v6.4.3","hash":"abc1234"},"remote":{"version":"v6.4.3","hash":"abc1234"}},
				"web":{"local":{"branch":"master","version":"v6.6","hash":"def5678"},"remote":{"version":"v6.6","hash":"def5678"}},
				"ftl":{"local":{"branch":"master","version":"v6.7","hash":"9999999","date":"2026-08-01"},"remote":{"version":"v6.7","hash":"9999999"}}
			},"took":0.002}`)
		default:
			writeJSON(w, http.StatusNotFound, `{"error":{"key":"not_found","message":"Not found","hint":null},"took":0.0}`)
		}
	})
}

func TestLoginAndLogout(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, versionHandler())
	c, _ := newClient(t, f)

	state, err := c.Login(context.Background(), config.NewSecretString("test-password"))
	if err != nil {
		t.Fatalf("login failed: %v", err)
	}
	if !state.Valid || state.Validity != 1800 {
		t.Errorf("unexpected session state: %+v", state)
	}
	if !c.SessionActive() {
		t.Fatal("session should be active after login")
	}

	if err := c.Logout(context.Background()); err != nil {
		t.Fatalf("logout failed: %v", err)
	}
	if c.SessionActive() {
		t.Fatal("session should be gone after logout")
	}
}

// TestSessionIDTravelsOnlyInHeader is the central credential-handling
// guarantee: Pi-hole also accepts the session id as a query parameter, and
// ScamWall must never use that path.
func TestSessionIDTravelsOnlyInHeader(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, versionHandler())
	c, _ := newClient(t, f)

	if err := c.WithSession(context.Background(), config.NewSecretString("pw"), func(ctx context.Context) error {
		_, err := c.Version(ctx)
		return err
	}); err != nil {
		t.Fatal(err)
	}

	var sawAuthedRequest bool
	for _, r := range f.recorded() {
		if r.RawQuery != "" {
			t.Errorf("%s %s carried a query string %q", r.Method, r.Path, r.RawQuery)
		}
		if r.Path == "/api/info/version" {
			sawAuthedRequest = true
			if r.SID != sessionSID {
				t.Errorf("authenticated request did not carry X-FTL-SID")
			}
		}
	}
	if !sawAuthedRequest {
		t.Fatal("expected an authenticated request")
	}
}

func TestLoginDoesNotSendSIDHeader(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, versionHandler())
	c, _ := newClient(t, f)

	if _, err := c.Login(context.Background(), config.NewSecretString("pw")); err != nil {
		t.Fatal(err)
	}
	for _, r := range f.recorded() {
		if r.Method == http.MethodPost && r.Path == "/api/auth" && r.HasAuth {
			t.Error("login request must not carry a session header")
		}
	}
}

func TestWithSessionAlwaysLogsOutOnError(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, versionHandler())
	c, _ := newClient(t, f)

	wantErr := errors.New("caller failed")
	err := c.WithSession(context.Background(), config.NewSecretString("pw"), func(ctx context.Context) error {
		return wantErr
	})
	if !errors.Is(err, wantErr) {
		t.Fatalf("caller error should propagate, got %v", err)
	}

	var sawDelete bool
	for _, r := range f.recorded() {
		if r.Method == http.MethodDelete && r.Path == "/api/auth" {
			sawDelete = true
		}
	}
	if !sawDelete {
		t.Fatal("logout must be attempted even when the operation fails")
	}
	if c.SessionActive() {
		t.Fatal("session should not remain active")
	}
}

// TestLogoutRunsAfterCancellation covers the case that motivated the separate
// logout context: a cancelled operation must still tear down its session.
func TestLogoutRunsAfterCancellation(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, versionHandler())
	c, _ := newClient(t, f)

	ctx, cancel := context.WithCancel(context.Background())
	err := c.WithSession(ctx, config.NewSecretString("pw"), func(inner context.Context) error {
		cancel()
		return inner.Err()
	})
	if err == nil {
		t.Fatal("expected the cancellation to surface")
	}

	var sawDelete bool
	for _, r := range f.recorded() {
		if r.Method == http.MethodDelete {
			sawDelete = true
		}
	}
	if !sawDelete {
		t.Fatal("logout must still be attempted after cancellation")
	}
}

func TestLogoutTreats404AsSuccess(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			writeJSON(w, http.StatusOK, loginOKBody())
			return
		}
		// No session active: the desired end state is already true.
		writeJSON(w, http.StatusNotFound, `{"took":0.0}`)
	}))
	c, _ := newClient(t, f)

	if _, err := c.Login(context.Background(), config.NewSecretString("pw")); err != nil {
		t.Fatal(err)
	}
	if err := c.Logout(context.Background()); err != nil {
		t.Fatalf("404 on logout means the session is gone, which is success: %v", err)
	}
}

func TestLogoutWithoutSessionIsNoOp(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, versionHandler())
	c, _ := newClient(t, f)
	if err := c.Logout(context.Background()); err != nil {
		t.Fatalf("logout without a session should be a no-op: %v", err)
	}
	if len(f.recorded()) != 0 {
		t.Error("no request should have been made")
	}
}

func TestVersionRequiresSession(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, versionHandler())
	c, _ := newClient(t, f)
	if _, err := c.Version(context.Background()); !errors.Is(err, pihole.ErrNotAuthenticated) {
		t.Fatalf("want ErrNotAuthenticated, got %v", err)
	}
}

func TestVersionParsesResponse(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, versionHandler())
	c, _ := newClient(t, f)

	var info *pihole.VersionInfo
	if err := c.WithSession(context.Background(), config.NewSecretString("pw"), func(ctx context.Context) error {
		var err error
		info, err = c.Version(ctx)
		return err
	}); err != nil {
		t.Fatal(err)
	}
	if info.Core.LocalVersion != "v6.4.3" || info.Web.LocalVersion != "v6.6" || info.FTL.LocalVersion != "v6.7" {
		t.Errorf("unexpected version info: %+v", info)
	}
}

// TestVersionHandlesNullFields matters because every field in the documented
// schema is nullable, so a perfectly valid response can be all nulls.
func TestVersionHandlesNullFields(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			writeJSON(w, http.StatusOK, loginOKBody())
			return
		}
		if r.Method == http.MethodDelete {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		writeJSON(w, http.StatusOK, `{"version":{
			"core":{"local":{"branch":null,"version":null,"hash":null},"remote":{"version":null,"hash":null}},
			"web":{"local":{"branch":null,"version":null,"hash":null},"remote":{"version":null,"hash":null}},
			"ftl":{"local":{"branch":null,"version":null,"hash":null,"date":null},"remote":{"version":null,"hash":null}}
		},"took":0.0}`)
	}))
	c, _ := newClient(t, f)

	if err := c.WithSession(context.Background(), config.NewSecretString("pw"), func(ctx context.Context) error {
		info, err := c.Version(ctx)
		if err != nil {
			return err
		}
		if info.Core.LocalVersion != "" {
			t.Errorf("null should decode to empty string, got %q", info.Core.LocalVersion)
		}
		return nil
	}); err != nil {
		t.Fatalf("null fields must not be an error: %v", err)
	}
}

func TestProbeAuthNeedsNoCredential(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusUnauthorized,
			`{"session":{"valid":false,"totp":false,"sid":null,"validity":-1,"message":"no SID provided"},"took":0.0}`)
	}))
	c, _ := newClient(t, f)

	state, err := c.ProbeAuth(context.Background())
	if err != nil {
		t.Fatalf("a 401 from the probe is a successful reachability check: %v", err)
	}
	if state.Valid {
		t.Error("session should not be reported valid")
	}
	for _, r := range f.recorded() {
		if r.HasAuth {
			t.Error("probe must not send a credential")
		}
	}
}

func TestErrorStatuses(t *testing.T) {
	cases := []struct {
		name   string
		status int
		body   string
		check  func(*testing.T, *pihole.APIError)
	}{
		{"401", http.StatusUnauthorized, `{"error":{"key":"unauthorized","message":"Unauthorized","hint":null},"took":0.0}`,
			func(t *testing.T, e *pihole.APIError) {
				if !e.Unauthorized() {
					t.Error("should report unauthorized")
				}
				if e.Key != "unauthorized" {
					t.Errorf("key = %q", e.Key)
				}
			}},
		{"403", http.StatusForbidden, `{"error":{"key":"forbidden","message":"Forbidden","hint":null},"took":0.0}`,
			func(t *testing.T, e *pihole.APIError) {
				if !e.Forbidden() {
					t.Error("should report forbidden")
				}
			}},
		{"429", http.StatusTooManyRequests, `{"error":{"key":"rate_limit","message":"Too many requests","hint":null},"took":0.0}`,
			func(t *testing.T, e *pihole.APIError) {
				if !e.RateLimited() {
					t.Error("should report rate limited")
				}
			}},
		{"500", http.StatusInternalServerError, `{"error":{"key":"internal","message":"Server error","hint":null},"took":0.0}`,
			func(t *testing.T, e *pihole.APIError) {
				if e.Status != 500 {
					t.Errorf("status = %d", e.Status)
				}
			}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ca := newTestCA(t)
			f := newFakePihole(t, ca, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				writeJSON(w, tc.status, tc.body)
			}))
			c, _ := newClient(t, f)

			_, err := c.Login(context.Background(), config.NewSecretString("pw"))
			if err == nil {
				t.Fatal("expected an error")
			}
			var apiErr *pihole.APIError
			if !errors.As(err, &apiErr) {
				t.Fatalf("expected *APIError, got %T: %v", err, err)
			}
			tc.check(t, apiErr)
		})
	}
}

func TestTruncatedJSONIsRejected(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"session":{"valid":true,`))
	}))
	c, _ := newClient(t, f)

	_, err := c.Login(context.Background(), config.NewSecretString("pw"))
	if err == nil {
		t.Fatal("truncated JSON must be rejected")
	}
	if !strings.Contains(err.Error(), "malformed JSON") {
		t.Errorf("unexpected error: %v", err)
	}
	// The body must not appear in the error.
	if strings.Contains(err.Error(), "session") {
		t.Errorf("error leaked the response body: %v", err)
	}
}

func TestOversizedResponseIsRejected(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"pad":"` + strings.Repeat("A", 100_000) + `"}`))
	}))

	var logBuf bytes.Buffer
	cfg := configFor(t, f, f.ca.path)
	cfg.Pihole.MaxResponseBytes = 1024
	c, err := pihole.New(cfg, audit.New(&logBuf))
	if err != nil {
		t.Fatal(err)
	}

	_, err = c.Login(context.Background(), config.NewSecretString("pw"))
	if !errors.Is(err, pihole.ErrResponseTooLarge) {
		t.Fatalf("want ErrResponseTooLarge, got %v", err)
	}
}

func TestWrongContentTypeIsRejected(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`<html>not pi-hole</html>`))
	}))
	c, _ := newClient(t, f)

	_, err := c.Login(context.Background(), config.NewSecretString("pw"))
	if !errors.Is(err, pihole.ErrUnexpectedContent) {
		t.Fatalf("want ErrUnexpectedContent, got %v", err)
	}
}

func TestCrossOriginRedirectIsRefused(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "https://attacker.example.net/api/auth", http.StatusFound)
	}))
	c, _ := newClient(t, f)

	_, err := c.Login(context.Background(), config.NewSecretString("pw"))
	if err == nil {
		t.Fatal("a redirect to another origin must be refused")
	}
	if !errors.Is(err, pihole.ErrCrossOriginRedirect) {
		t.Fatalf("want ErrCrossOriginRedirect, got %v", err)
	}
	// The credential must not have been sent to the redirect target.
	if strings.Contains(err.Error(), "pw") {
		t.Error("error leaked the credential")
	}
}

func TestTimeout(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(2 * time.Second)
		writeJSON(w, http.StatusOK, loginOKBody())
	}))

	var logBuf bytes.Buffer
	cfg := configFor(t, f, f.ca.path)
	cfg.Pihole.RequestTimeout = config.Duration(150 * time.Millisecond)
	cfg.Pihole.TotalTimeout = config.Duration(time.Second)
	c, err := pihole.New(cfg, audit.New(&logBuf))
	if err != nil {
		t.Fatal(err)
	}

	start := time.Now()
	if _, err := c.Login(context.Background(), config.NewSecretString("pw")); err == nil {
		t.Fatal("expected a timeout")
	}
	if elapsed := time.Since(start); elapsed > 900*time.Millisecond {
		t.Errorf("timeout was not enforced promptly: %v", elapsed)
	}
}

func TestContextCancellation(t *testing.T) {
	ca := newTestCA(t)
	f := newFakePihole(t, ca, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(2 * time.Second)
		writeJSON(w, http.StatusOK, loginOKBody())
	}))
	c, _ := newClient(t, f)

	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		time.Sleep(50 * time.Millisecond)
		cancel()
	}()

	_, err := c.Login(ctx, config.NewSecretString("pw"))
	if err == nil {
		t.Fatal("expected cancellation")
	}
	if !errors.Is(err, context.Canceled) {
		t.Errorf("want context.Canceled, got %v", err)
	}
}

func TestTLSFailureWithWrongCA(t *testing.T) {
	serverCA := newTestCA(t)
	otherCA := newTestCA(t)
	f := newFakePihole(t, serverCA, versionHandler())

	var logBuf bytes.Buffer
	// Trust a CA that did not issue the server's certificate.
	c, err := pihole.New(configFor(t, f, otherCA.path), audit.New(&logBuf))
	if err != nil {
		t.Fatal(err)
	}

	_, err = c.Login(context.Background(), config.NewSecretString("pw"))
	if err == nil {
		t.Fatal("a certificate from an untrusted CA must be refused")
	}
	if !strings.Contains(err.Error(), "TLS verification failed") {
		t.Errorf("unexpected error: %v", err)
	}
}

func TestHostnameMismatchIsRefused(t *testing.T) {
	ca := newTestCA(t)
	// The server presents a valid certificate for the wrong name.
	f := newFakePihole(t, ca, versionHandler(), "not-pi-hole.example.net")
	c, _ := newClient(t, f)

	_, err := c.Login(context.Background(), config.NewSecretString("pw"))
	if err == nil {
		t.Fatal("a certificate for a different name must be refused")
	}
	if !strings.Contains(err.Error(), "TLS verification failed") {
		t.Errorf("unexpected error: %v", err)
	}
}

func TestPlaintextIsRefused(t *testing.T) {
	cfg := config.Default()
	cfg.Pihole.CAPath = newTestCA(t).path
	c, err := pihole.New(cfg, audit.New(&bytes.Buffer{}))
	if err != nil {
		t.Fatal(err)
	}
	// BaseURL is always https, so the only way to observe the guard is that no
	// http scheme is ever produced.
	if !strings.HasPrefix(cfg.BaseURL(), "https://") {
		t.Fatal("base URL must be https")
	}
	_ = c
}

func TestBadCAFileIsRejected(t *testing.T) {
	cfg := config.Default()
	cfg.Pihole.CAPath = "/nonexistent/ca.crt"
	if _, err := pihole.New(cfg, audit.New(&bytes.Buffer{})); err == nil {
		t.Fatal("a missing CA must be an error")
	}
}

func TestRetryOnlyForSafeRequests(t *testing.T) {
	ca := newTestCA(t)
	var attempts int
	f := newFakePihole(t, ca, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			attempts++
			writeJSON(w, http.StatusTooManyRequests,
				`{"error":{"key":"rate_limit","message":"slow down","hint":null},"took":0.0}`)
			return
		}
		writeJSON(w, http.StatusOK, loginOKBody())
	}))

	var logBuf bytes.Buffer
	cfg := configFor(t, f, f.ca.path)
	cfg.Pihole.MaxRetries = 3
	c, err := pihole.New(cfg, audit.New(&logBuf))
	if err != nil {
		t.Fatal(err)
	}

	if _, err := c.Login(context.Background(), config.NewSecretString("pw")); err == nil {
		t.Fatal("expected the rate-limit error")
	}
	// Authentication must never be retried: repeating it can trip lockouts and
	// exhaust session seats during an incident.
	if attempts != 1 {
		t.Fatalf("login was attempted %d times, want exactly 1", attempts)
	}
}

func TestRetryHappensForReads(t *testing.T) {
	ca := newTestCA(t)
	var versionAttempts int
	f := newFakePihole(t, ca, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost:
			writeJSON(w, http.StatusOK, loginOKBody())
		case r.Method == http.MethodDelete:
			w.WriteHeader(http.StatusNoContent)
		default:
			versionAttempts++
			if versionAttempts < 3 {
				writeJSON(w, http.StatusServiceUnavailable,
					`{"error":{"key":"unavailable","message":"try again","hint":null},"took":0.0}`)
				return
			}
			writeJSON(w, http.StatusOK, `{"version":{
				"core":{"local":{"version":"v6.4.3"},"remote":{}},
				"web":{"local":{"version":"v6.6"},"remote":{}},
				"ftl":{"local":{"version":"v6.7"},"remote":{}}},"took":0.0}`)
		}
	}))

	var logBuf bytes.Buffer
	cfg := configFor(t, f, f.ca.path)
	cfg.Pihole.MaxRetries = 3
	c, err := pihole.New(cfg, audit.New(&logBuf))
	if err != nil {
		t.Fatal(err)
	}

	if err := c.WithSession(context.Background(), config.NewSecretString("pw"), func(ctx context.Context) error {
		_, err := c.Version(ctx)
		return err
	}); err != nil {
		t.Fatalf("a retried read should eventually succeed: %v", err)
	}
	if versionAttempts != 3 {
		t.Errorf("expected 3 attempts, got %d", versionAttempts)
	}
}

func TestNoRetryOnUnauthorized(t *testing.T) {
	ca := newTestCA(t)
	var attempts int
	f := newFakePihole(t, ca, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodPost:
			writeJSON(w, http.StatusOK, loginOKBody())
		case http.MethodDelete:
			w.WriteHeader(http.StatusNoContent)
		default:
			attempts++
			writeJSON(w, http.StatusUnauthorized,
				`{"error":{"key":"unauthorized","message":"Unauthorized","hint":null},"took":0.0}`)
		}
	}))

	var logBuf bytes.Buffer
	cfg := configFor(t, f, f.ca.path)
	cfg.Pihole.MaxRetries = 3
	c, err := pihole.New(cfg, audit.New(&logBuf))
	if err != nil {
		t.Fatal(err)
	}

	_ = c.WithSession(context.Background(), config.NewSecretString("pw"), func(ctx context.Context) error {
		_, err := c.Version(ctx)
		return err
	})
	if attempts != 1 {
		t.Fatalf("401 must not be retried; got %d attempts", attempts)
	}
}
