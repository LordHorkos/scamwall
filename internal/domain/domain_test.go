// SPDX-License-Identifier: AGPL-3.0-only

package domain_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/LordHorkos/scamwall/internal/domain"
)

func TestNormalizeAccepts(t *testing.T) {
	cases := map[string]string{
		"simple":                 "example.com",
		"subdomain":              "login.secure.example.com",
		"uppercase":              "EXAMPLE.COM",
		"mixed case":             "LoGiN.Example.Com",
		"trailing root dot":      "example.com.",
		"surrounding space":      "  example.com  ",
		"hyphenated":             "secure-login.example.com",
		"digits":                 "web3.example.com",
		"long tld":               "example.technology",
		"multi-part public tld":  "shop.example.co.uk",
		"idn german":             "münchen.example.com",
		"punycode already":       "xn--mnchen-3ya.example.com",
	}
	want := map[string]string{
		"simple":                "example.com",
		"subdomain":             "login.secure.example.com",
		"uppercase":             "example.com",
		"mixed case":            "login.example.com",
		"trailing root dot":     "example.com",
		"surrounding space":     "example.com",
		"hyphenated":            "secure-login.example.com",
		"digits":                "web3.example.com",
		"long tld":              "example.technology",
		"multi-part public tld": "shop.example.co.uk",
		"idn german":            "xn--mnchen-3ya.example.com",
		"punycode already":      "xn--mnchen-3ya.example.com",
	}

	for name, input := range cases {
		t.Run(name, func(t *testing.T) {
			got, err := domain.Normalize(input)
			if err != nil {
				t.Fatalf("Normalize(%q) failed: %v", input, err)
			}
			if string(got) != want[name] {
				t.Errorf("Normalize(%q) = %q, want %q", input, got, want[name])
			}
		})
	}
}

// TestNormalizeIsIdempotent matters because a canonical form that is not
// stable under re-normalisation would let the same domain appear twice.
func TestNormalizeIsIdempotent(t *testing.T) {
	for _, in := range []string{"Example.COM.", "münchen.example.com", "  a.b.example.org "} {
		first, err := domain.Normalize(in)
		if err != nil {
			t.Fatal(err)
		}
		second, err := domain.Normalize(string(first))
		if err != nil {
			t.Fatalf("re-normalising %q failed: %v", first, err)
		}
		if first != second {
			t.Errorf("not idempotent: %q -> %q -> %q", in, first, second)
		}
	}
}

func TestNormalizeRejects(t *testing.T) {
	cases := []struct {
		name  string
		input string
		want  error
	}{
		{"empty", "", domain.ErrEmpty},
		{"whitespace only", "   ", domain.ErrEmpty},
		{"single label", "localhost1", domain.ErrSingleLabel},
		{"bare tld", "com", domain.ErrSingleLabel},

		{"localhost", "localhost", domain.ErrLocalhost},
		{"localhost subdomain", "api.localhost", domain.ErrLocalhost},

		{"local tld", "printer.local", domain.ErrLocalTLD},
		{"internal tld", "db.internal", domain.ErrLocalTLD},
		{"lan tld", "nas.lan", domain.ErrLocalTLD},
		{"onion", "abc.onion", domain.ErrLocalTLD},
		{"invalid tld", "thing.invalid", domain.ErrLocalTLD},
		{"arpa", "1.0.0.127.in-addr.arpa", domain.ErrLocalTLD},

		{"ipv4", "192.0.2.1", domain.ErrIPLiteral},
		{"ipv4 trailing dot", "192.0.2.1.", domain.ErrIPLiteral},
		{"ipv6", "2001:db8::1", domain.ErrIPLiteral},
		{"ipv6 bracketed", "[2001:db8::1]", domain.ErrIPLiteral},
		{"loopback v4", "127.0.0.1", domain.ErrIPLiteral},

		{"wildcard star", "*.example.com", domain.ErrWildcard},
		{"wildcard embedded", "ex*ample.com", domain.ErrWildcard},
		{"wildcard question", "ex?ample.com", domain.ErrWildcard},

		{"public suffix com", "com", domain.ErrSingleLabel},
		{"public suffix couk", "co.uk", domain.ErrPublicSuffix},
		{"public suffix github.io", "github.io", domain.ErrPublicSuffix},

		{"leading dot", ".example.com", domain.ErrEmptyLabel},
		{"double dot", "a..example.com", domain.ErrEmptyLabel},
		{"double trailing dot", "example.com..", domain.ErrEmptyLabel},

		{"url scheme", "https://example.com", domain.ErrInvalidCharacter},
		{"url path", "example.com/path", domain.ErrInvalidCharacter},
		{"userinfo", "user@example.com", domain.ErrInvalidCharacter},
		{"port", "example.com:443", domain.ErrInvalidCharacter},
		{"query", "example.com?a=b", domain.ErrWildcard},
		{"newline", "example.com\n", domain.ErrInvalidCharacter},
		{"tab", "exa\tmple.com", domain.ErrInvalidCharacter},
		{"null byte", "example\x00.com", domain.ErrInvalidCharacter},
		{"inner space", "exa mple.com", domain.ErrInvalidCharacter},

		{"numeric tld", "example.123", domain.ErrNumericTLD},
		{"leading hyphen label", "-bad.example.com", domain.ErrMalformedIDN},
		{"trailing hyphen label", "bad-.example.com", domain.ErrMalformedIDN},
		{"underscore", "bad_label.example.com", domain.ErrMalformedIDN},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := domain.Normalize(tc.input)
			if err == nil {
				t.Fatalf("Normalize(%q) unexpectedly succeeded, returning %q", tc.input, got)
			}
			if !errors.Is(err, tc.want) {
				t.Errorf("Normalize(%q) = %v, want %v", tc.input, err, tc.want)
			}
		})
	}
}

func TestNormalizeRejectsMixedScript(t *testing.T) {
	// "аpple" with a Cyrillic а converts to valid punycode and would otherwise
	// be accepted as a legitimate-looking distinct name.
	mixed := "аpple.example.com"
	_, err := domain.Normalize(mixed)
	if err == nil {
		t.Fatal("mixed-script label should be rejected")
	}
	if !errors.Is(err, domain.ErrMixedScript) {
		t.Fatalf("want ErrMixedScript, got %v", err)
	}
}

func TestNormalizeAcceptsSingleNonLatinScript(t *testing.T) {
	// A name written entirely in one script is legitimate and must not be
	// caught by the mixed-script rule.
	for _, in := range []string{"пример.example.com", "例え.example.com"} {
		if _, err := domain.Normalize(in); err != nil {
			t.Errorf("Normalize(%q) should succeed, got %v", in, err)
		}
	}
}

func TestNormalizeEnforcesLengthLimits(t *testing.T) {
	longLabel := strings.Repeat("a", domain.MaxLabelLength+1)
	if _, err := domain.Normalize(longLabel + ".example.com"); err == nil {
		t.Error("over-long label should be rejected")
	}

	// 253 is the limit for the presentation form without a trailing dot.
	var parts []string
	for range 30 {
		parts = append(parts, strings.Repeat("a", 60))
	}
	if _, err := domain.Normalize(strings.Join(parts, ".") + ".com"); err == nil {
		t.Error("over-long domain should be rejected")
	}
}

func TestNormalizeAcceptsMaximumLengths(t *testing.T) {
	label := strings.Repeat("a", domain.MaxLabelLength)
	if _, err := domain.Normalize(label + ".example.com"); err != nil {
		t.Errorf("a %d-character label is legal: %v", domain.MaxLabelLength, err)
	}
}

func TestDomainString(t *testing.T) {
	d, err := domain.Normalize("Example.COM")
	if err != nil {
		t.Fatal(err)
	}
	if d.String() != "example.com" {
		t.Errorf("String() = %q", d.String())
	}
}
