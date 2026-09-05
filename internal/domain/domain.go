// SPDX-License-Identifier: AGPL-3.0-only

// Package domain provides a canonical domain type with strict validation.
//
// Every domain entering ScamWall passes through Normalize. Producing a single
// canonical form matters for correctness (two spellings of the same name must
// not both appear in a plan) and for safety (a name that looks harmless but
// resolves differently must not slip through).
//
// This package intentionally has no ScamWall dependencies, so its guarantees
// hold regardless of the caller.
package domain

import (
	"errors"
	"fmt"
	"net"
	"strings"
	"unicode"

	"golang.org/x/net/idna"
	"golang.org/x/net/publicsuffix"
)

// Length limits from RFC 1035, in the presentation form used here (no trailing
// root dot, so 253 rather than 255).
const (
	MaxLength      = 253
	MaxLabelLength = 63
	MinLabels      = 2
)

// Validation errors. Each rejected class has a distinct error so that a caller
// can report precisely why a feed record was refused.
var (
	ErrEmpty            = errors.New("domain is empty")
	ErrTooLong          = errors.New("domain exceeds maximum length")
	ErrLabelTooLong     = errors.New("domain label exceeds maximum length")
	ErrEmptyLabel       = errors.New("domain contains an empty label")
	ErrSingleLabel      = errors.New("domain is a single label")
	ErrIPLiteral        = errors.New("domain is an IP address literal")
	ErrLocalhost        = errors.New("domain is localhost")
	ErrLocalTLD         = errors.New("domain uses a link-local or internal TLD")
	ErrWildcard         = errors.New("domain contains a wildcard")
	ErrMalformedIDN     = errors.New("domain is not a valid internationalised name")
	ErrPublicSuffix     = errors.New("domain is a public suffix")
	ErrInvalidCharacter = errors.New("domain contains an invalid character")
	ErrNumericTLD       = errors.New("domain has an all-numeric top-level label")
	ErrMixedScript      = errors.New("domain label mixes scripts")
)

// Domain is a validated, canonical, lowercase, ASCII (punycode) domain name
// with no trailing root dot.
type Domain string

// String returns the canonical form.
func (d Domain) String() string { return string(d) }

// idnaProfile is the lookup profile used for normalisation.
//
// StrictDomainName restricts labels to letters, digits and hyphen, which
// excludes underscores and other characters that resolvers treat
// inconsistently. VerifyDNSLength enforces the length limits during
// conversion. BidiRule applies the RFC 5893 rules for right-to-left names.
var idnaProfile = idna.New(
	idna.MapForLookup(),
	idna.StrictDomainName(true),
	idna.ValidateLabels(true),
	idna.VerifyDNSLength(true),
	idna.BidiRule(),
)

// internalTLDs are top-level labels that never denote a public internet name.
// Blocking them is meaningless at best, and at worst would interfere with
// local service discovery.
var internalTLDs = map[string]struct{}{
	"local":       {},
	"localhost":   {},
	"localdomain": {},
	"internal":    {},
	"onion":       {},
	"invalid":     {},
	"test":        {},
	"example":     {},
	"home":        {},
	"lan":         {},
	"arpa":        {},
}

// Normalize validates raw and returns its canonical form.
//
// The order of checks is deliberate. Structural rejections (wildcards, IP
// literals, stray URL syntax) happen before IDNA conversion, because feeding
// such input to a normaliser produces confusing errors and, in the worst case,
// a name that converts "successfully" into something unintended.
func Normalize(raw string) (Domain, error) {
	s := strings.TrimSpace(raw)
	if s == "" {
		return "", ErrEmpty
	}

	// Control characters and embedded whitespace are always malformed and are
	// a common way to smuggle a different name past a naive parser.
	for _, r := range s {
		if r < 0x20 || r == 0x7f || unicode.IsSpace(r) {
			return "", fmt.Errorf("%w: control or whitespace character", ErrInvalidCharacter)
		}
	}

	// Wildcards are rejected outright. ScamWall blocks exact domains only, so
	// a wildcard is never a narrowing of scope, only a widening of it.
	if strings.ContainsAny(s, "*?") {
		return "", ErrWildcard
	}

	// Strip surrounding brackets so that "[::1]" is recognised as an address
	// rather than as a name containing punctuation.
	unbracketed := strings.TrimSuffix(strings.TrimPrefix(s, "["), "]")
	if net.ParseIP(unbracketed) != nil {
		return "", ErrIPLiteral
	}

	// Remove exactly one trailing root dot. More than one is malformed.
	s = strings.TrimSuffix(s, ".")
	if s == "" {
		return "", ErrEmpty
	}
	if strings.HasSuffix(s, ".") {
		return "", fmt.Errorf("%w: repeated trailing dot", ErrEmptyLabel)
	}
	// Re-check: "192.0.2.1." is an address once the root dot is removed.
	if net.ParseIP(s) != nil {
		return "", ErrIPLiteral
	}

	// Reject URL syntax rather than silently extracting a host from it. A feed
	// is expected to contain bare domains; anything else is a schema violation
	// and should be visible as one.
	if i := strings.IndexAny(s, "/\\@:?#%,;\"'<>()[]{}|^`"); i >= 0 {
		return "", fmt.Errorf("%w: %q", ErrInvalidCharacter, s[i:i+1])
	}
	if strings.HasPrefix(s, ".") || strings.Contains(s, "..") {
		return "", ErrEmptyLabel
	}

	// Guard against mixed-script labels before conversion, while the original
	// runes are still visible. After punycode conversion the distinction is
	// gone.
	if err := checkSingleScript(s); err != nil {
		return "", err
	}

	ascii, err := idnaProfile.ToASCII(s)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrMalformedIDN, err)
	}
	ascii = strings.ToLower(ascii)
	if ascii == "" {
		return "", ErrEmpty
	}

	if len(ascii) > MaxLength {
		return "", fmt.Errorf("%w: %d > %d", ErrTooLong, len(ascii), MaxLength)
	}

	labels := strings.Split(ascii, ".")
	if len(labels) < MinLabels {
		return "", ErrSingleLabel
	}
	for _, l := range labels {
		if l == "" {
			return "", ErrEmptyLabel
		}
		if len(l) > MaxLabelLength {
			return "", fmt.Errorf("%w: %q is %d > %d", ErrLabelTooLong, l, len(l), MaxLabelLength)
		}
		if strings.HasPrefix(l, "-") || strings.HasSuffix(l, "-") {
			return "", fmt.Errorf("%w: label %q starts or ends with a hyphen", ErrInvalidCharacter, l)
		}
	}

	tld := labels[len(labels)-1]
	if _, bad := internalTLDs[tld]; bad {
		if tld == "localhost" {
			return "", ErrLocalhost
		}
		return "", fmt.Errorf("%w: .%s", ErrLocalTLD, tld)
	}
	if ascii == "localhost" {
		return "", ErrLocalhost
	}
	if isAllDigits(tld) {
		return "", ErrNumericTLD
	}

	// A public suffix is a registry boundary, not a site. Blocking "com" or
	// "co.uk" would take out an enormous portion of the internet, so an entry
	// that *is* a public suffix is refused rather than trusted.
	if suffix, _ := publicsuffix.PublicSuffix(ascii); suffix == ascii {
		return "", fmt.Errorf("%w: %q", ErrPublicSuffix, ascii)
	}

	return Domain(ascii), nil
}

// isAllDigits reports whether s consists only of ASCII digits.
func isAllDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// checkSingleScript rejects labels that mix Unicode scripts.
//
// This is a conservative defence against homograph attacks: "аpple.com" with a
// Cyrillic first letter converts to valid punycode and would otherwise be
// accepted as a distinct, legitimate-looking name. Requiring one script per
// label blocks the common confusable constructions.
//
// It is not a complete UTS #39 implementation. Whole-script confusables — a
// name written entirely in one non-Latin script that resembles a Latin one —
// are not detected here.
func checkSingleScript(s string) error {
	for _, label := range strings.Split(s, ".") {
		var seen string
		for _, r := range label {
			if r < 0x80 {
				// ASCII is compatible with any script for this purpose;
				// digits and hyphens appear in names of every script.
				continue
			}
			script := scriptOf(r)
			if script == "" {
				continue
			}
			if seen == "" {
				seen = script
				continue
			}
			if seen != script {
				return fmt.Errorf("%w: %q mixes %s and %s", ErrMixedScript, label, seen, script)
			}
		}
	}
	return nil
}

// scriptOf returns the name of the Unicode script r belongs to, ignoring
// script-neutral categories.
func scriptOf(r rune) string {
	for name, table := range unicode.Scripts {
		switch name {
		case "Common", "Inherited":
			continue
		}
		if unicode.Is(table, r) {
			return name
		}
	}
	return ""
}
