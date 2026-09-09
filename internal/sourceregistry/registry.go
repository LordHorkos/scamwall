// SPDX-License-Identifier: AGPL-3.0-only

// Package sourceregistry loads and validates the ScamWall source registry.
//
// # WHY THIS EXISTS
//
// docs/SOURCE_REGISTRY.md defines a schema, a disposition vocabulary, and a set
// of rules that bind every record. Until this package, all three were prose.
// Prose does not refuse anything: a record with a licence field left blank, a
// disposition invented on the spot, or `enabled: true` sitting beside
// `commercial_use: prohibited` would have been written down and read back as
// fact by whatever consumed the file next.
//
// The registry's entire purpose is provenance — where a claim came from, when
// it was read, and whether the rights permit the use intended for it. A
// provenance document that accepts unchecked input is worse than none, because
// it launders a guess into a record.
//
// # WHAT THIS PACKAGE ESTABLISHES, AND WHAT IT CANNOT
//
// It establishes that a record is STRUCTURALLY sound and INTERNALLY consistent:
// every field is present, every closed vocabulary is respected, dates parse and
// are not in the future, identifiers are unique and not reused, dependencies
// point at records that exist, and a source is not marked enabled unless its
// own recorded rights permit it.
//
// It establishes NOTHING about the truth of any field. `commercial_use:
// permitted` is checked to be a member of the vocabulary; whether the
// provider's licence actually permits commercial use is a human reading of a
// human document, and no validator can do it. The same holds for
// `official_documentation` really belonging to the provider, for
// `upstream_sources` being complete, and therefore for independence: two feeds
// are only known to share an upstream if somebody recorded that they do.
//
// So this package makes a false record harder to write by accident. It does
// not make one impossible to write on purpose, and it is not evidence about any
// provider.
package sourceregistry

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

// DateLayout is the only accepted form for verified_on. A date with no
// timezone and no time of day is deliberate: the field records the day a human
// read a documentation page, which is the precision that claim actually has.
const DateLayout = "2006-01-02"

// Problem is one validation failure, addressed to the thing that caused it.
//
// Validation collects every problem rather than stopping at the first, because
// a person correcting a registry file wants the whole list, and because a
// validator that reports one error at a time trains its user to fix errors
// one at a time without reading the rest.
type Problem struct {
	// Path locates the failure, e.g. `sources[3].commercial_use` or
	// `retired_source_ids[1]`.
	Path string
	// Message says what is wrong, in terms a person editing the file can act
	// on.
	Message string
}

func (p Problem) String() string { return p.Path + ": " + p.Message }

// Source is one record. Every field is required — see RequiredSourceFields —
// and `unknown` is a permitted value that is NOT the same as an absent key.
// That distinction is the reason this package decodes twice: once to see which
// keys the file actually carries, and once to read their values.
type Source struct {
	SourceID                string   `json:"source_id"`
	CatalogRef              string   `json:"catalog_ref"`
	RequestedPriority       string   `json:"requested_priority"`
	OfficialName            string   `json:"official_name"`
	OfficialDocumentation   string   `json:"official_documentation"`
	VerifiedOn              string   `json:"verified_on"`
	Kind                    string   `json:"kind"`
	IndicatorTypes          []string `json:"indicator_types"`
	ClassificationMeaning   string   `json:"classification_meaning"`
	Authentication          string   `json:"authentication"`
	Quotas                  string   `json:"quotas"`
	UpdateCadence           string   `json:"update_cadence"`
	Retention               string   `json:"retention"`
	WithdrawalBehaviour     string   `json:"withdrawal_behaviour"`
	CommercialUse           string   `json:"commercial_use"`
	Caching                 string   `json:"caching"`
	Redistribution          string   `json:"redistribution"`
	AttributionRequired     string   `json:"attribution_required"`
	DerivedDataRestrictions string   `json:"derived_data_restrictions"`
	UpstreamSources         []string `json:"upstream_sources"`
	AggregationDependencies []string `json:"aggregation_dependencies"`
	AccessStatus            string   `json:"access_status"`
	DispositionReason       string   `json:"disposition_reason"`
	PrivacyImplications     string   `json:"privacy_implications"`
	IntendedPermittedUse    string   `json:"intended_permitted_use"`
	OperationalCost         string   `json:"operational_cost"`
	Enabled                 *bool    `json:"enabled"`
}

// Registry is the whole file.
type Registry struct {
	SchemaVersion int `json:"schema_version"`
	// Note is free text describing the state of the file. It is not evidence
	// and nothing reads it programmatically; it exists so that an empty
	// registry says why it is empty instead of looking like a loading failure.
	Note string `json:"note"`
	// RetiredSourceIDs holds identifiers that were used once and must never be
	// used again. docs/SOURCE_REGISTRY.md requires that a source_id is "never
	// reused, never renumbered", and a rule that only ever sees the CURRENT
	// file cannot enforce that on its own: an id deleted in one commit is free
	// for the taking in the next. Retiring it here is what makes the rule
	// checkable.
	RetiredSourceIDs []string `json:"retired_source_ids"`
	Sources          []Source `json:"sources"`
}

// RequiredSourceFields is every key a source record must carry.
//
// It is the machine-readable half of docs/SOURCE_REGISTRY.md §2, and the two
// are kept in step by hand. A key listed here and missing from the prose, or
// the reverse, is a defect in whichever was changed last.
var RequiredSourceFields = []string{
	"source_id",
	"catalog_ref",
	"requested_priority",
	"official_name",
	"official_documentation",
	"verified_on",
	"kind",
	"indicator_types",
	"classification_meaning",
	"authentication",
	"quotas",
	"update_cadence",
	"retention",
	"withdrawal_behaviour",
	"commercial_use",
	"caching",
	"redistribution",
	"attribution_required",
	"derived_data_restrictions",
	"upstream_sources",
	"aggregation_dependencies",
	"access_status",
	"disposition_reason",
	"privacy_implications",
	"intended_permitted_use",
	"operational_cost",
	"enabled",
}

// The closed vocabularies. A value outside one of these is refused rather than
// carried, because a disposition invented at the keyboard is exactly the kind
// of claim this registry exists to prevent.
var (
	// ValidKinds — docs/SOURCE_REGISTRY.md §2, `kind`.
	ValidKinds = []string{
		"bulk feed", "lookup API", "enrichment service", "corpus",
		"platform", "advisory source", "commercial partnership",
	}
	// ValidAuthentication — §2, `authentication`.
	ValidAuthentication = []string{"none", "key", "account", "contract"}
	// ValidRights — §2, the three rights fields. `unknown` is permitted and
	// means the documentation was read and did not say, or was not read.
	ValidRights = []string{"permitted", "prohibited", "conditional", "unknown"}
	// ValidAttribution — §2, `attribution_required`.
	ValidAttribution = []string{"yes", "no", "unknown"}
	// ValidAccessStatus is the disposition vocabulary — §3. Exactly one per
	// source.
	ValidAccessStatus = []string{
		"verified-available",
		"credentials-required",
		"commercial-approval-required",
		"historical",
		"unavailable",
		"unresolved",
	}
)

// Load reads and parses a registry file. It does not validate it: parsing and
// validating are separate results, and a caller that conflates them cannot tell
// "this file is not JSON" from "this file is JSON and says something
// impossible".
func Load(path string) (*Registry, []Problem, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, fmt.Errorf("reading the registry: %w", err)
	}
	return Parse(b)
}

// Parse decodes registry bytes.
//
// The returned problems are PRESENCE problems only — keys the schema requires
// and this file does not carry. They are produced here rather than in Validate
// because they can only be seen before the bytes become a struct: once decoded,
// a missing string and a string present-and-empty are the same value, and
// docs/SOURCE_REGISTRY.md is explicit that they are not the same claim.
func Parse(b []byte) (*Registry, []Problem, error) {
	// Unknown keys are refused. A misspelled field name would otherwise be
	// silently dropped, and the record would validate while saying nothing
	// about the thing the author thought they had recorded.
	var shape struct {
		SchemaVersion    *int                          `json:"schema_version"`
		Note             *string                       `json:"note"`
		RetiredSourceIDs *[]string                     `json:"retired_source_ids"`
		Sources          *[]map[string]json.RawMessage `json:"sources"`
	}
	dec := json.NewDecoder(strings.NewReader(string(b)))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&shape); err != nil {
		return nil, nil, fmt.Errorf("the registry is not valid JSON in the expected shape: %w", err)
	}

	var problems []Problem
	if shape.SchemaVersion == nil {
		problems = append(problems, Problem{"schema_version", "required and absent"})
	}
	if shape.Note == nil {
		problems = append(problems, Problem{"note", "required and absent"})
	}
	if shape.RetiredSourceIDs == nil {
		problems = append(problems, Problem{"retired_source_ids", "required and absent; write [] to say none have been retired"})
	}
	if shape.Sources == nil {
		problems = append(problems, Problem{"sources", "required and absent; write [] to say the registry is empty"})
	}

	// Presence, per record, before any value is read.
	if shape.Sources != nil {
		for i, raw := range *shape.Sources {
			for _, f := range RequiredSourceFields {
				if _, ok := raw[f]; !ok {
					problems = append(problems, Problem{
						fmt.Sprintf("sources[%d].%s", i, f),
						"required and absent — an absent field is not the same claim as `unknown`, so write the value out",
					})
				}
			}
			for k := range raw {
				if !contains(RequiredSourceFields, k) {
					problems = append(problems, Problem{
						fmt.Sprintf("sources[%d].%s", i, k),
						"not a field in the schema — a misspelled key records nothing",
					})
				}
			}
		}
	}

	// The second decode deliberately does NOT disallow unknown fields. The
	// presence loop above already reports a misspelled key, by path, as a
	// problem the author can fix alongside the others; letting the decoder
	// raise it as a hard error instead would discard that list and report one
	// typo as though the file were unreadable. Unknown TOP-LEVEL keys are
	// still refused, by the first decode.
	var reg Registry
	dec2 := json.NewDecoder(strings.NewReader(string(b)))
	if err := dec2.Decode(&reg); err != nil {
		return nil, problems, fmt.Errorf("the registry could not be decoded: %w", err)
	}
	return &reg, problems, nil
}

// Validate checks every rule this package can check, against the registry as a
// whole. asOf is supplied rather than read from the clock so that the result is
// a function of its inputs.
func (r *Registry) Validate(asOf time.Time) []Problem {
	var problems []Problem

	if r.SchemaVersion != 1 {
		problems = append(problems, Problem{
			"schema_version",
			fmt.Sprintf("is %d; this package understands version 1 only, and refuses to guess at another", r.SchemaVersion),
		})
	}

	retired := map[string]bool{}
	for i, id := range r.RetiredSourceIDs {
		p := fmt.Sprintf("retired_source_ids[%d]", i)
		if strings.TrimSpace(id) == "" {
			problems = append(problems, Problem{p, "is empty"})
			continue
		}
		if retired[id] {
			problems = append(problems, Problem{p, fmt.Sprintf("%q is listed twice", id)})
		}
		retired[id] = true
	}

	seenID := map[string]int{}
	seenCatalogRef := map[string]int{}
	known := map[string]bool{}
	for _, s := range r.Sources {
		known[s.SourceID] = true
	}

	for i := range r.Sources {
		s := &r.Sources[i]
		at := func(f string) string { return fmt.Sprintf("sources[%d].%s", i, f) }

		// -- identity ---------------------------------------------------------
		if strings.TrimSpace(s.SourceID) == "" {
			problems = append(problems, Problem{at("source_id"), "is empty"})
		} else {
			if prev, dup := seenID[s.SourceID]; dup {
				problems = append(problems, Problem{
					at("source_id"),
					fmt.Sprintf("%q is already used by sources[%d] — ids are never reused", s.SourceID, prev),
				})
			}
			seenID[s.SourceID] = i
			if retired[s.SourceID] {
				problems = append(problems, Problem{
					at("source_id"),
					fmt.Sprintf("%q is in retired_source_ids — a retired id is never reused, so this record needs a new one", s.SourceID),
				})
			}
		}

		if s.CatalogRef != "none" {
			n, err := strconv.Atoi(s.CatalogRef)
			if err != nil || n < 1 {
				problems = append(problems, Problem{
					at("catalog_ref"),
					fmt.Sprintf("is %q; it must be a positive entry number from the supplied catalog, or the string \"none\" for a source added later", s.CatalogRef),
				})
			} else if prev, dup := seenCatalogRef[s.CatalogRef]; dup {
				problems = append(problems, Problem{
					at("catalog_ref"),
					fmt.Sprintf("catalog entry %s is already claimed by sources[%d] — two records cannot be the same catalog entry", s.CatalogRef, prev),
				})
			} else {
				seenCatalogRef[s.CatalogRef] = i
			}
		}

		// -- closed vocabularies ---------------------------------------------
		checkEnum(&problems, at("kind"), s.Kind, ValidKinds)
		checkEnum(&problems, at("authentication"), s.Authentication, ValidAuthentication)
		checkEnum(&problems, at("commercial_use"), s.CommercialUse, ValidRights)
		checkEnum(&problems, at("caching"), s.Caching, ValidRights)
		checkEnum(&problems, at("redistribution"), s.Redistribution, ValidRights)
		checkEnum(&problems, at("attribution_required"), s.AttributionRequired, ValidAttribution)
		checkEnum(&problems, at("access_status"), s.AccessStatus, ValidAccessStatus)

		// -- free text that must still say something ---------------------------
		//
		// `unknown` is a permitted answer everywhere. An EMPTY answer is not:
		// it is indistinguishable from an author who stopped typing, and the
		// whole point of the `unknown` value is that not knowing is stated.
		for f, v := range map[string]string{
			"requested_priority":        s.RequestedPriority,
			"official_name":             s.OfficialName,
			"classification_meaning":    s.ClassificationMeaning,
			"quotas":                    s.Quotas,
			"update_cadence":            s.UpdateCadence,
			"retention":                 s.Retention,
			"withdrawal_behaviour":      s.WithdrawalBehaviour,
			"derived_data_restrictions": s.DerivedDataRestrictions,
			"privacy_implications":      s.PrivacyImplications,
			"intended_permitted_use":    s.IntendedPermittedUse,
			"operational_cost":          s.OperationalCost,
			"disposition_reason":        s.DispositionReason,
		} {
			if strings.TrimSpace(v) == "" {
				problems = append(problems, Problem{at(f), "is empty; write `unknown` if that is the answer, so that not knowing is stated rather than implied"})
			}
		}

		if len(s.IndicatorTypes) == 0 {
			problems = append(problems, Problem{at("indicator_types"), "is empty; list the types the provider publishes, or [\"unknown\"] if the documentation does not say"})
		}
		for j, t := range s.IndicatorTypes {
			if strings.TrimSpace(t) == "" {
				problems = append(problems, Problem{at(fmt.Sprintf("indicator_types[%d]", j)), "is empty"})
			}
		}

		// -- dependencies point at records that exist -------------------------
		//
		// This is the independence check doing what it can. It cannot know that
		// two feeds share an upstream; it can refuse a dependency on a record
		// that is not in the registry, which is how a dangling claim of
		// independence gets caught.
		for j, dep := range s.AggregationDependencies {
			p := at(fmt.Sprintf("aggregation_dependencies[%d]", j))
			switch {
			case strings.TrimSpace(dep) == "":
				problems = append(problems, Problem{p, "is empty"})
			case dep == s.SourceID:
				problems = append(problems, Problem{p, "names its own record"})
			case !known[dep]:
				problems = append(problems, Problem{p, fmt.Sprintf("names %q, which is not a source_id in this registry", dep)})
			}
		}

		// -- a dated claim, or no claim ---------------------------------------
		//
		// §2: "A record with no date states nothing current." A record that has
		// been researched must therefore carry the date its documentation was
		// read, and the URL that was read. `unresolved` is the one disposition
		// that may say `unknown` to both, because it means nobody has looked.
		researched := s.AccessStatus != "unresolved" && contains(ValidAccessStatus, s.AccessStatus)

		if s.VerifiedOn == "unknown" {
			if researched {
				problems = append(problems, Problem{
					at("verified_on"),
					fmt.Sprintf("is `unknown`, but access_status is %q — a disposition other than `unresolved` is a claim about what the documentation said, and an undated claim states nothing current", s.AccessStatus),
				})
			}
		} else {
			d, err := time.Parse(DateLayout, s.VerifiedOn)
			switch {
			case err != nil:
				problems = append(problems, Problem{
					at("verified_on"),
					fmt.Sprintf("is %q; it must be a date in %s form, or `unknown`", s.VerifiedOn, DateLayout),
				})
			case d.After(asOf):
				problems = append(problems, Problem{
					at("verified_on"),
					fmt.Sprintf("is %s, which is in the future — documentation cannot have been read on a day that has not happened", s.VerifiedOn),
				})
			}
		}

		if s.OfficialDocumentation == "unknown" {
			if researched {
				problems = append(problems, Problem{
					at("official_documentation"),
					fmt.Sprintf("is `unknown`, but access_status is %q — record the URL the disposition was read from", s.AccessStatus),
				})
			}
		} else {
			u, err := url.Parse(s.OfficialDocumentation)
			switch {
			case err != nil || u.Host == "":
				problems = append(problems, Problem{
					at("official_documentation"),
					fmt.Sprintf("is %q, which is not an absolute URL", s.OfficialDocumentation),
				})
			case u.Scheme != "https":
				// Documentation read over plaintext is documentation an
				// intermediary can rewrite, and every licence claim in the
				// record below is a reading of that page. If a provider is
				// http-only that is a finding about the provider; record it in
				// disposition_reason and leave this `unknown`.
				problems = append(problems, Problem{
					at("official_documentation"),
					fmt.Sprintf("uses scheme %q; documentation a record's licence claims are read from must be fetched over https", u.Scheme),
				})
			}
		}

		// -- enabling is a separate decision, and it is checked ---------------
		//
		// §1: "Entering a source here does not enable it. Enabling is a
		// separate decision that requires a disposition of `verified-available`
		// AND rights that permit the intended use."
		if s.Enabled != nil && *s.Enabled {
			if s.AccessStatus != "verified-available" {
				problems = append(problems, Problem{
					at("enabled"),
					fmt.Sprintf("is true while access_status is %q; only `verified-available` may be enabled", s.AccessStatus),
				})
			}
			for f, v := range map[string]string{
				"commercial_use": s.CommercialUse,
				"caching":        s.Caching,
				"redistribution": s.Redistribution,
			} {
				switch v {
				case "permitted", "conditional":
					// `conditional` is allowed to be enabled because the
					// condition may well be met; what is recorded in
					// derived_data_restrictions and intended_permitted_use is
					// where that judgement lives. This validator checks that the
					// judgement was made against a stated right, not that it was
					// made correctly.
				default:
					problems = append(problems, Problem{
						at("enabled"),
						fmt.Sprintf("is true while %s is %q; a source is not enabled on a right that is prohibited or unknown", f, v),
					})
				}
			}
		}
	}

	sort.Slice(problems, func(a, b int) bool {
		if problems[a].Path != problems[b].Path {
			return problems[a].Path < problems[b].Path
		}
		return problems[a].Message < problems[b].Message
	})
	return problems
}

func checkEnum(problems *[]Problem, path, value string, allowed []string) {
	if contains(allowed, value) {
		return
	}
	*problems = append(*problems, Problem{
		path,
		fmt.Sprintf("is %q; permitted values are %s", value, strings.Join(allowed, ", ")),
	})
}

func contains(hay []string, needle string) bool {
	for _, h := range hay {
		if h == needle {
			return true
		}
	}
	return false
}
