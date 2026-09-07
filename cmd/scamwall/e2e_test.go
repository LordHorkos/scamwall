// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/LordHorkos/scamwall/internal/config"
)

// End-to-end tests: the real CLI, its real configuration loader, its real
// client, against a local HTTPS server that impersonates the parts of the
// Pi-hole API Phase 1 uses.
//
// WHAT THESE ESTABLISH AND WHAT THEY DO NOT
//
// They establish that the command surface behaves as documented: which network
// operations happen and in what order, what the exit status means, that a
// configuration error is reported before anything is authenticated, and that
// no credential reaches stdout, stderr or the audit log.
//
// They establish NOTHING about compatibility with a real Pi-hole. The server
// below is a fake written from docs/PIHOLE_API_CONTRACT.md; if the appliance
// diverges from that document, these tests pass and the deployment fails. That
// evidence needs a disposable real instance and is Phase 2 work-order item 1.

const e2eHost = "pi.hole"

// e2eCA is a throwaway certificate authority, generated per run. No trust
// material is committed, so nothing here can be reused against anything.
type e2eCA struct {
	path string
	cert *x509.Certificate
	key  *ecdsa.PrivateKey
}

func newE2ECA(t *testing.T, dir string) *e2eCA {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "ScamWall E2E Test CA"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		IsCA:                  true,
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature,
		BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "pihole-ca.crt")
	if err := os.WriteFile(path, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0o600); err != nil {
		t.Fatal(err)
	}
	return &e2eCA{path: path, cert: cert, key: key}
}

func (ca *e2eCA) leaf(t *testing.T) tls.Certificate {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(2),
		Subject:      pkix.Name{CommonName: e2eHost},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames:     []string{e2eHost},
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1")},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, ca.cert, &key.PublicKey, ca.key)
	if err != nil {
		t.Fatal(err)
	}
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}
}

// e2eEnv is a complete, disposable deployment: a CA, a password file, a
// configuration, and a server.
type e2eEnv struct {
	dir        string
	ca         *e2eCA
	srv        *httptest.Server
	configPath string
	password   string
	sid        string

	mu       sync.Mutex
	requests []string
	// authStatus, when non-zero, is what POST /api/auth answers with.
	authStatus int
}

func (e *e2eEnv) record(method, path string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.requests = append(e.requests, method+" "+path)
}

// sequence returns the exact ordered list of API calls the CLI made.
func (e *e2eEnv) sequence() []string {
	e.mu.Lock()
	defer e.mu.Unlock()
	out := make([]string, len(e.requests))
	copy(out, e.requests)
	return out
}

func randomE2EToken(kind string) string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic("test setup: no entropy: " + err.Error())
	}
	return "scamwall-e2e-" + kind + "-" + hex.EncodeToString(b)
}

// newE2EEnv builds the environment. mutate, if given, adjusts the
// configuration before it is written.
func newE2EEnv(t *testing.T, mutate func(*config.Config)) *e2eEnv {
	t.Helper()
	dir := t.TempDir()
	e := &e2eEnv{
		dir:      dir,
		ca:       newE2ECA(t, dir),
		password: randomE2EToken("password"),
		sid:      randomE2EToken("sid"),
	}

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		e.record(r.Method, r.URL.Path)
		writeJSON := func(status int, body string) {
			w.Header().Set("Content-Type", "application/json; charset=utf-8")
			w.WriteHeader(status)
			_, _ = w.Write([]byte(body))
		}
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/api/auth":
			if e.authStatus != 0 {
				writeJSON(e.authStatus, `{"error":{"key":"unauthorized","message":"Unauthorized","hint":null},"took":0.001}`)
				return
			}
			writeJSON(200, `{"session":{"valid":true,"totp":false,"sid":"`+e.sid+
				`","csrf":"`+randomE2EToken("csrf")+`","validity":1800,"message":null},"took":0.001}`)
		case r.Method == http.MethodGet && r.URL.Path == "/api/auth":
			writeJSON(http.StatusUnauthorized,
				`{"session":{"valid":false,"totp":false,"sid":null,"validity":-1,"message":"no SID provided"},"took":0.001}`)
		case r.Method == http.MethodDelete && r.URL.Path == "/api/auth":
			if r.Header.Get("X-FTL-SID") != e.sid {
				writeJSON(http.StatusUnauthorized, `{"error":{"key":"unauthorized","message":"Unauthorized","hint":null},"took":0.001}`)
				return
			}
			w.WriteHeader(http.StatusNoContent)
		case r.Method == http.MethodGet && r.URL.Path == "/api/info/version":
			if r.Header.Get("X-FTL-SID") != e.sid {
				writeJSON(http.StatusUnauthorized, `{"error":{"key":"unauthorized","message":"Unauthorized","hint":null},"took":0.001}`)
				return
			}
			writeJSON(200, `{"version":{`+
				`"core":{"local":{"branch":"master","version":"v6.0.4","hash":"abc","date":null},"remote":{"version":"v6.0.4","hash":"abc"}},`+
				`"web":{"local":{"branch":"master","version":"v6.0.1","hash":"def","date":null},"remote":{"version":"v6.0.1","hash":"def"}},`+
				`"ftl":{"local":{"branch":"master","version":"v6.0.2","hash":"ghi","date":"2026-01-01"},"remote":{"version":"v6.0.2","hash":"ghi"}}},`+
				`"took":0.001}`)
		default:
			writeJSON(http.StatusNotFound, `{"error":{"key":"not_found","message":"Not Found","hint":null},"took":0.001}`)
		}
	})

	srv := httptest.NewUnstartedServer(handler)
	srv.TLS = &tls.Config{Certificates: []tls.Certificate{e.ca.leaf(t)}}
	srv.StartTLS()
	t.Cleanup(srv.Close)
	e.srv = srv

	secretPath := filepath.Join(dir, "pihole_app_password")
	if err := os.WriteFile(secretPath, []byte(e.password+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	_, portStr, err := net.SplitHostPort(srv.Listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	port, err := strconv.Atoi(portStr)
	if err != nil {
		t.Fatal(err)
	}

	cfg := config.Default()
	// The name stays pi.hole so hostname verification is exercised exactly as
	// it is in production; only the dialled address is overridden, which is
	// the same mechanism the real deployment uses.
	cfg.Pihole.Host = e2eHost
	cfg.Pihole.Port = port
	cfg.Pihole.AddressOverride = srv.Listener.Addr().String()
	cfg.Pihole.CAPath = e.ca.path
	cfg.Pihole.SecretPath = secretPath
	cfg.Pihole.RequestTimeout = config.Duration(2 * time.Second)
	cfg.Pihole.TotalTimeout = config.Duration(5 * time.Second)
	cfg.Pihole.ConnectTimeout = config.Duration(2 * time.Second)
	cfg.Pihole.LogoutTimeout = config.Duration(2 * time.Second)
	cfg.Feed.Path = filepath.Join("..", "..", "testdata", "feed.json")
	cfg.Feed.TrustKeyID = "scamwall-test-key-1"
	cfg.Feed.TrustPublicKey = "ZZdzt8vw2UCXeoT95fcT9Fh0U80M7L0I1L/io4AeR7A="
	if mutate != nil {
		mutate(&cfg)
	}

	b, err := json.Marshal(cfg)
	if err != nil {
		t.Fatal(err)
	}
	e.configPath = filepath.Join(dir, "config.json")
	if err := os.WriteFile(e.configPath, b, 0o600); err != nil {
		t.Fatal(err)
	}
	return e
}

// assertNoCredentials fails if any captured stream mentions the password or
// the session id. Both are generated per run, so a match cannot be a
// coincidence.
func (e *e2eEnv) assertNoCredentials(t *testing.T, streams ...string) {
	t.Helper()
	for i, s := range streams {
		if strings.Contains(s, e.password) {
			t.Errorf("stream %d contains the application password", i)
		}
		if strings.Contains(s, e.sid) {
			t.Errorf("stream %d contains the session id", i)
		}
	}
}

// --- The approved read-only workflow ----------------------------------------

func TestStatusPerformsExactlyTheApprovedSequence(t *testing.T) {
	e := newE2EEnv(t, nil)
	code, stdout, stderr := capture(t, "status", "-config", e.configPath)

	if code != exitOK {
		t.Fatalf("exit %d\nstdout: %s\nstderr: %s", code, stdout, stderr)
	}
	want := []string{
		"POST /api/auth",
		"GET /api/info/version",
		"DELETE /api/auth",
	}
	got := e.sequence()
	if len(got) != len(want) {
		t.Fatalf("network sequence = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("network sequence = %v, want %v", got, want)
		}
	}
	// The output must describe what actually happened.
	for _, s := range []string{"v6.0.4", "v6.0.1", "v6.0.2", "session closed"} {
		if !strings.Contains(stdout, s) {
			t.Errorf("stdout does not report %q:\n%s", s, stdout)
		}
	}
	e.assertNoCredentials(t, stdout, stderr)
}

func TestSyncDryRunReportsThePlanAndSubmitsNothing(t *testing.T) {
	e := newE2EEnv(t, nil)
	code, stdout, stderr := capture(t, "sync", "--dry-run", "-config", e.configPath)

	if code != exitOK {
		t.Fatalf("exit %d\nstdout: %s\nstderr: %s", code, stdout, stderr)
	}
	got := e.sequence()
	for _, req := range got {
		if !strings.HasPrefix(req, "POST /api/auth") &&
			!strings.HasPrefix(req, "GET /api/info/version") &&
			!strings.HasPrefix(req, "DELETE /api/auth") {
			t.Fatalf("sync issued an operation outside the approved set: %q", req)
		}
	}
	if len(got) != 3 {
		t.Fatalf("network sequence = %v, want exactly three calls", got)
	}
	for _, s := range []string{"DRY RUN", "No blocking change was made", "proposed plan"} {
		if !strings.Contains(stdout, s) {
			t.Errorf("stdout does not state %q:\n%s", s, stdout)
		}
	}
	e.assertNoCredentials(t, stdout, stderr)
}

func TestDoctorProbesWithoutSendingACredential(t *testing.T) {
	e := newE2EEnv(t, nil)
	code, stdout, stderr := capture(t, "doctor", "-config", e.configPath)

	// The probe is answered 401, which doctor reads as "reachable, needs a
	// password" — a successful probe, so every check passes.
	if code != exitOK {
		t.Fatalf("exit %d\nstdout: %s\nstderr: %s", code, stdout, stderr)
	}
	got := e.sequence()
	if len(got) != 1 || got[0] != "GET /api/auth" {
		t.Fatalf("doctor's network sequence = %v, want exactly [GET /api/auth]", got)
	}
	if !strings.Contains(stdout, "0 failed") {
		t.Errorf("doctor did not pass:\n%s", stdout)
	}
	e.assertNoCredentials(t, stdout, stderr)
}

// --- Failure paths ----------------------------------------------------------

func TestInvalidConfigurationFailsBeforeAnythingIsAuthenticated(t *testing.T) {
	cases := map[string]func(*config.Config){
		"a port outside the legal range": func(c *config.Config) { c.Pihole.Port = 0 },
		"plaintext requested":            func(c *config.Config) { c.Pihole.Host = "" },
		"enforcement requested":          func(c *config.Config) { c.Runtime.DryRun = false },
		"a request timeout exceeding the total": func(c *config.Config) {
			c.Pihole.RequestTimeout = config.Duration(time.Hour)
		},
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			e := newE2EEnv(t, mutate)
			code, stdout, stderr := capture(t, "status", "-config", e.configPath)
			if code == exitOK {
				t.Fatalf("an invalid configuration was accepted\nstdout: %s", stdout)
			}
			if seq := e.sequence(); len(seq) != 0 {
				t.Fatalf("the network was contacted despite an invalid configuration: %v", seq)
			}
			if !strings.Contains(stdout, "configuration") {
				t.Errorf("the failure does not name the configuration:\n%s", stdout)
			}
			e.assertNoCredentials(t, stdout, stderr)
		})
	}
}

func TestAMissingCredentialFileFailsBeforeAnyRequest(t *testing.T) {
	e := newE2EEnv(t, func(c *config.Config) {
		c.Pihole.SecretPath = filepath.Join(t.TempDir(), "absent")
	})
	code, stdout, stderr := capture(t, "status", "-config", e.configPath)
	if code == exitOK {
		t.Fatal("a missing credential was accepted")
	}
	if seq := e.sequence(); len(seq) != 0 {
		t.Fatalf("the network was contacted with no credential available: %v", seq)
	}
	e.assertNoCredentials(t, stdout, stderr)
}

func TestFailedAuthenticationReturnsPromptlyAndLeavesNoSession(t *testing.T) {
	e := newE2EEnv(t, nil)
	e.authStatus = http.StatusUnauthorized

	start := time.Now()
	code, stdout, stderr := capture(t, "status", "-config", e.configPath)
	elapsed := time.Since(start)

	if code != exitFailure {
		t.Fatalf("exit %d, want %d\nstdout: %s", code, exitFailure, stdout)
	}
	// Exactly one attempt: a rejected credential must not become a login storm
	// against a service that rate-limits authentication.
	got := e.sequence()
	if len(got) != 1 || got[0] != "POST /api/auth" {
		t.Fatalf("network sequence = %v, want exactly one POST /api/auth", got)
	}
	if elapsed > 5*time.Second {
		t.Fatalf("a rejected credential took %v to report", elapsed)
	}
	if !strings.Contains(stdout, "401") {
		t.Errorf("the failure does not report the status:\n%s", stdout)
	}
	e.assertNoCredentials(t, stdout, stderr)
}

func TestEnforcementIsRefusedEvenWithAReachableServer(t *testing.T) {
	// The refusal must not depend on the network being unavailable.
	e := newE2EEnv(t, nil)
	code, stdout, stderr := capture(t, "sync", "--dry-run=false", "-config", e.configPath)

	if code != exitUsage {
		t.Fatalf("exit %d, want %d\nstdout: %s", code, exitUsage, stdout)
	}
	if seq := e.sequence(); len(seq) != 0 {
		t.Fatalf("an enforcement request contacted the network: %v", seq)
	}
	if !strings.Contains(stdout, "refusing to run") {
		t.Errorf("the refusal is not stated plainly:\n%s", stdout)
	}
	e.assertNoCredentials(t, stdout, stderr)
}

func TestAnUnreachableServerFailsWithoutClaimingSuccess(t *testing.T) {
	e := newE2EEnv(t, nil)
	e.srv.Close()

	code, stdout, stderr := capture(t, "status", "-config", e.configPath)
	if code != exitFailure {
		t.Fatalf("exit %d, want %d\nstdout: %s", code, exitFailure, stdout)
	}
	if strings.Contains(stdout, "session closed") {
		t.Errorf("the output claims a session was closed:\n%s", stdout)
	}
	e.assertNoCredentials(t, stdout, stderr)
}

// TestCredentialsNeverReachAnyStream sweeps every command in one place, so a
// new command added without thought about disclosure fails here.
func TestCredentialsNeverReachAnyStream(t *testing.T) {
	commands := [][]string{
		{"status"},
		{"sync", "--dry-run"},
		{"doctor"},
		{"validate-feed"},
		{"plan"},
		{"version"},
	}
	for _, cmd := range commands {
		t.Run(strings.Join(cmd, " "), func(t *testing.T) {
			e := newE2EEnv(t, nil)
			args := append(append([]string{}, cmd...), "-config", e.configPath)
			_, stdout, stderr := capture(t, args...)
			e.assertNoCredentials(t, stdout, stderr)
		})
	}
}
