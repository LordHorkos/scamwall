// SPDX-License-Identifier: AGPL-3.0-only

// Package policy turns a validated feed into a proposed blocking plan.
//
// A plan is a pure function of its inputs. This package does not import the
// Pi-hole adapter, and nothing here can reach the network. That is the
// structural reason a Phase 1 plan cannot be submitted: there is no wiring
// through which it could travel.
package policy

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/LordHorkos/scamwall/internal/domain"
	"github.com/LordHorkos/scamwall/internal/feed"
)

// PlanFormatVersion identifies the canonical serialisation used for the
// digest. Changing the serialisation must change this value, otherwise two
// incompatible plans could share a digest.
const PlanFormatVersion = "scamwall-plan-v1"

// Entry is a single proposed blocking action.
type Entry struct {
	Domain     domain.Domain   `json:"domain"`
	Category   string          `json:"category,omitempty"`
	Confidence feed.Confidence `json:"confidence"`
}

// Exclusions records why candidate indicators did not reach the plan.
//
// Reporting exclusions matters: a plan that silently drops most of its input
// looks identical to a plan whose input was small, and an operator needs to
// tell those apart.
type Exclusions struct {
	NotBlockAction  int `json:"not_block_action"`
	BelowConfidence int `json:"below_confidence"`
	ExpiredInFeed   int `json:"expired_in_feed"`
}

// Total returns the number of excluded indicators.
func (e Exclusions) Total() int { return e.NotBlockAction + e.BelowConfidence + e.ExpiredInFeed }

// Plan is a proposed set of blocking actions.
//
// In Phase 1 a Plan is a report, not an instruction. Nothing consumes it other
// than the terminal.
type Plan struct {
	FormatVersion   string     `json:"format_version"`
	FeedID          string     `json:"feed_id"`
	ManifestVersion string     `json:"manifest_version"`
	FeedExpiresAt   time.Time  `json:"feed_expires_at"`
	Entries         []Entry    `json:"entries"`
	Exclusions      Exclusions `json:"exclusions"`
	// Digest is a SHA-256 over the canonical serialisation. Two runs over the
	// same feed produce the same digest, which is what makes operator review
	// meaningful: the plan that was reviewed is provably the plan in hand.
	Digest string `json:"digest"`
	// DryRun is always true in Phase 1 and is recorded in the plan so that a
	// captured plan document states its own mode.
	DryRun bool `json:"dry_run"`
}

// Count returns the number of proposed entries.
func (p *Plan) Count() int { return len(p.Entries) }

// IsEmpty reports whether the plan proposes nothing.
func (p *Plan) IsEmpty() bool { return len(p.Entries) == 0 }

// Compute builds a plan from a validated feed.
//
// Only high-confidence block records are eligible. Anything less certain is
// reported but not proposed: the cost of wrongly blocking a bank, a hospital,
// or a delivery tracker is far higher than the cost of missing one scam
// domain, so the default posture is to under-block.
func Compute(v *feed.Validated) *Plan {
	p := &Plan{
		FormatVersion:   PlanFormatVersion,
		FeedID:          v.FeedID,
		ManifestVersion: v.ManifestVersion,
		FeedExpiresAt:   v.ExpiresAt.UTC(),
		Entries:         make([]Entry, 0, len(v.Indicators)),
		Exclusions:      Exclusions{ExpiredInFeed: v.ExpiredCount},
		DryRun:          true,
	}

	for _, ind := range v.Indicators {
		if ind.Action != feed.ActionBlock {
			p.Exclusions.NotBlockAction++
			continue
		}
		if ind.Confidence != feed.ConfidenceHigh {
			p.Exclusions.BelowConfidence++
			continue
		}
		p.Entries = append(p.Entries, Entry{
			Domain:     ind.Domain,
			Category:   ind.Category,
			Confidence: ind.Confidence,
		})
	}

	// Sort by canonical domain. Domains are unique after feed validation, so
	// this is a total order and the result is fully deterministic.
	sort.Slice(p.Entries, func(i, j int) bool {
		return p.Entries[i].Domain < p.Entries[j].Domain
	})

	p.Digest = digest(p)
	return p
}

// canonical renders the plan in the exact form covered by the digest.
//
// Only fields that change the meaning of the plan are included. Timestamps
// that vary between runs over the same feed are deliberately excluded, because
// a digest that changes without the plan changing would be useless for review.
func canonical(p *Plan) string {
	var b strings.Builder
	b.WriteString(PlanFormatVersion)
	b.WriteByte('\n')
	b.WriteString("feed_id:" + p.FeedID + "\n")
	b.WriteString("manifest_version:" + p.ManifestVersion + "\n")
	fmt.Fprintf(&b, "entries:%d\n", len(p.Entries))
	for _, e := range p.Entries {
		b.WriteString(string(e.Domain))
		b.WriteByte('\t')
		b.WriteString(string(e.Confidence))
		b.WriteByte('\n')
	}
	return b.String()
}

func digest(p *Plan) string {
	sum := sha256.Sum256([]byte(canonical(p)))
	return "sha256:" + hex.EncodeToString(sum[:])
}

// Canonical exposes the digest input, so tests can assert determinism against
// the serialisation rather than only against the hash.
func Canonical(p *Plan) string { return canonical(p) }
