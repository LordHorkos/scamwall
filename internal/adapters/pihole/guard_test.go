// SPDX-License-Identifier: AGPL-3.0-only

package pihole_test

import (
	"bytes"
	"context"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/LordHorkos/scamwall/internal/adapters/pihole"
	"github.com/LordHorkos/scamwall/internal/audit"
	"github.com/LordHorkos/scamwall/internal/config"
)

// repoRoot walks up from the package directory to the module root.
func repoRoot(t *testing.T) string {
	t.Helper()
	dir, err := filepath.Abs(".")
	if err != nil {
		t.Fatal(err)
	}
	for range 10 {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	t.Fatal("could not locate module root")
	return ""
}

// walkGoSources visits every non-test .go file in the module.
func walkGoSources(t *testing.T, fn func(path string, src []byte)) {
	t.Helper()
	root := repoRoot(t)
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if d.Name() == ".git" || d.Name() == "vendor" {
				return fs.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		src, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(root, path)
		fn(rel, src)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}

// TestNoTLSVerificationBypass is the guard behind SECURITY.md's claim that
// verification cannot be disabled. It looks for an assignment rather than a
// mention, so that the explanatory comment in client.go does not trip it.
func TestNoTLSVerificationBypass(t *testing.T) {
	assignment := regexp.MustCompile(`InsecureSkipVerify\s*[:=]`)
	walkGoSources(t, func(path string, src []byte) {
		for i, line := range strings.Split(string(src), "\n") {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "//") {
				continue
			}
			if assignment.Match([]byte(line)) {
				t.Errorf("%s:%d sets InsecureSkipVerify: %s", path, i+1, trimmed)
			}
		}
	})
}

// TestRevealCallSitesAreBounded pins the number of places a credential's
// plaintext is extracted. Growth here is the single most likely way a leak is
// introduced, so it fails loudly rather than drifting.
func TestRevealCallSitesAreBounded(t *testing.T) {
	want := map[string]int{
		"internal/adapters/pihole/client.go":    1, // authentication request body
		"internal/adapters/pihole/transport.go": 1, // X-FTL-SID header
	}
	got := map[string]int{}

	walkGoSources(t, func(path string, src []byte) {
		// The definition in secret.go is not a call site.
		if path == filepath.FromSlash("internal/config/secret.go") {
			return
		}
		n := strings.Count(string(src), ".Reveal()")
		if n > 0 {
			got[filepath.ToSlash(path)] = n
		}
	})

	for path, count := range got {
		if want[path] != count {
			t.Errorf("%s has %d Reveal call sites, expected %d", path, count, want[path])
		}
	}
	for path, count := range want {
		if got[path] != count {
			t.Errorf("expected %d Reveal call sites in %s, found %d", count, path, got[path])
		}
	}
}

// TestNoMutatingEndpoints asserts the Phase 1 boundary at the source level:
// the client must reference no Pi-hole endpoint capable of changing state.
func TestNoMutatingEndpoints(t *testing.T) {
	forbidden := []string{
		"/api/domains", "/api/groups", "/api/clients", "/api/lists",
		"/api/dns/blocking", "/api/action/", "/api/config", "/api/teleporter",
		"/api/dhcp",
	}
	walkGoSources(t, func(path string, src []byte) {
		if !strings.HasPrefix(filepath.ToSlash(path), "internal/adapters/pihole/") {
			return
		}
		for _, ep := range forbidden {
			if strings.Contains(string(src), ep) {
				t.Errorf("%s references a mutating endpoint %q", path, ep)
			}
		}
	})
}

// TestNoInsecureTooling checks that nothing in the repository reaches for a
// verification bypass at the tooling level either.
func TestNoInsecureTooling(t *testing.T) {
	root := repoRoot(t)
	patterns := []string{"curl -k", "--insecure", "GODEBUG=x509ignoreCN"}
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if d.Name() == ".git" {
				return fs.SkipDir
			}
			return nil
		}
		ext := filepath.Ext(path)
		if ext != ".sh" && ext != ".yaml" && ext != ".yml" && d.Name() != "Dockerfile" {
			return nil
		}
		src, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(root, path)
		for _, p := range patterns {
			if bytes.Contains(src, []byte(p)) {
				t.Errorf("%s contains %q", rel, p)
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}

// TestLogsNeverContainCredentials drives a complete session against the fake
// server and inspects everything the logger emitted.
//
// This is the empirical counterpart to the redaction unit tests: those prove
// the mechanism works, this proves it is actually wired into the real flow.
func TestLogsNeverContainCredentials(t *testing.T) {
	// Generated per run: nothing credential-shaped is committed, and a fresh
	// value cannot coincidentally match something the log legitimately holds.
	password := randomToken("pw")

	ca := newTestCA(t)
	f := newFakePihole(t, ca, versionHandler())

	var logBuf bytes.Buffer
	c, err := pihole.New(configFor(t, f, f.ca.path), audit.New(&logBuf))
	if err != nil {
		t.Fatal(err)
	}

	if err := c.WithSession(context.Background(), config.NewSecretString(password), func(ctx context.Context) error {
		_, err := c.Version(ctx)
		return err
	}); err != nil {
		t.Fatal(err)
	}

	logs := logBuf.String()
	if logs == "" {
		t.Fatal("expected the session to produce log output")
	}

	forbidden := []struct {
		needle string
		what   string
	}{
		{password, "the application password"},
		{sessionSID, "the session id"},
		{sessionCSRF, "the CSRF token"},
		{"X-FTL-SID:", "an authorization header"},
		{"Authorization", "an authorization header"},
	}
	for _, f := range forbidden {
		if strings.Contains(logs, f.needle) {
			t.Errorf("logs contain %s:\n%s", f.what, logs)
		}
	}
}

// TestErrorsNeverContainCredentials checks the other common leak channel.
func TestErrorsNeverContainCredentials(t *testing.T) {
	password := randomToken("pw")

	ca := newTestCA(t)
	otherCA := newTestCA(t)
	f := newFakePihole(t, ca, versionHandler())

	// Force a TLS failure so the error path is exercised.
	c, err := pihole.New(configFor(t, f, otherCA.path), audit.New(&bytes.Buffer{}))
	if err != nil {
		t.Fatal(err)
	}
	_, err = c.Login(context.Background(), config.NewSecretString(password))
	if err == nil {
		t.Fatal("expected a TLS error")
	}
	if strings.Contains(err.Error(), password) {
		t.Errorf("error leaked the password: %v", err)
	}
}
