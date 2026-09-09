// SPDX-License-Identifier: AGPL-3.0-only

package sourceregistry

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// asOf is fixed so that every result here is a function of its inputs. A test
// that reads the clock passes or fails on the day it is run, which is the
// property FINDING-60 was about.
var asOf = time.Date(2026, 9, 8, 0, 0, 0, 0, time.UTC)

// validSource is a record that passes everything. Each case below takes this
// and breaks exactly one thing, so a failure names the rule that caught it
// rather than a soup of unrelated problems.
func validSource() map[string]any {
	return map[string]any{
		"source_id":                 "src-0001",
		"catalog_ref":               "1",
		"requested_priority":        "wave 1",
		"official_name":             "Example Threat Feed",
		"official_documentation":    "https://example.org/docs/feed",
		"verified_on":               "2026-09-01",
		"kind":                      "bulk feed",
		"indicator_types":           []any{"domain"},
		"classification_meaning":    "the provider labels an entry `phishing` when it has observed credential harvesting",
		"authentication":            "none",
		"quotas":                    "unknown",
		"update_cadence":            "hourly, per the provider's documentation",
		"retention":                 "unknown",
		"withdrawal_behaviour":      "entries disappear without a tombstone",
		"commercial_use":            "permitted",
		"caching":                   "permitted",
		"redistribution":            "prohibited",
		"attribution_required":      "yes",
		"derived_data_restrictions": "unknown",
		"upstream_sources":          []any{},
		"aggregation_dependencies":  []any{},
		"access_status":             "verified-available",
		"disposition_reason":        "documentation read in full; licence permits the intended use",
		"privacy_implications":      "carries no personal data beyond domain registration contacts",
		"intended_permitted_use":    "local blocklist candidate generation for one household",
		"operational_cost":          "unknown",
		"enabled":                   false,
	}
}

func registryWith(sources ...map[string]any) []byte {
	if sources == nil {
		sources = []map[string]any{}
	}
	b, err := json.Marshal(map[string]any{
		"schema_version":     1,
		"note":               "test fixture",
		"retired_source_ids": []any{},
		"sources":            sources,
	})
	if err != nil {
		panic(err)
	}
	return b
}

// problemsFor parses and validates, returning every problem from both stages.
func problemsFor(t *testing.T, b []byte) []Problem {
	t.Helper()
	reg, parseProblems, err := Parse(b)
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}
	return append(parseProblems, reg.Validate(asOf)...)
}

func assertProblem(t *testing.T, problems []Problem, wantPath, wantSubstring string) {
	t.Helper()
	for _, p := range problems {
		if p.Path == wantPath && strings.Contains(p.Message, wantSubstring) {
			return
		}
	}
	t.Errorf("no problem at %q containing %q.\nGot:\n%s", wantPath, wantSubstring, render(problems))
}

func assertNoProblems(t *testing.T, problems []Problem) {
	t.Helper()
	if len(problems) != 0 {
		t.Errorf("expected no problems, got:\n%s", render(problems))
	}
}

func render(problems []Problem) string {
	var sb strings.Builder
	for _, p := range problems {
		sb.WriteString("  " + p.String() + "\n")
	}
	if sb.Len() == 0 {
		return "  (none)"
	}
	return sb.String()
}

// --- the baseline ------------------------------------------------------------

func TestAValidRecordPasses(t *testing.T) {
	assertNoProblems(t, problemsFor(t, registryWith(validSource())))
}

func TestAnEmptyRegistryIsValid(t *testing.T) {
	// The state the registry is actually in. An empty registry must not be an
	// error, or the honest answer would be unrepresentable.
	assertNoProblems(t, problemsFor(t, registryWith()))
}

// --- absent is not `unknown` --------------------------------------------------

func TestEveryRequiredFieldIsRequired(t *testing.T) {
	// One case per field, generated from the schema itself, so a field added to
	// RequiredSourceFields without a test is impossible.
	for _, field := range RequiredSourceFields {
		t.Run(field, func(t *testing.T) {
			s := validSource()
			delete(s, field)
			problems := problemsFor(t, registryWith(s))
			assertProblem(t, problems, "sources[0]."+field, "required and absent")
		})
	}
}

func TestAnAbsentFieldIsNotTheSameAsUnknown(t *testing.T) {
	// The distinction the schema insists on: `unknown` is an answer, absence is
	// not. Written as its own case because it is the reason Parse decodes twice
	// and would be silently lost by a refactor that decoded once.
	absent := validSource()
	delete(absent, "quotas")
	assertProblem(t, problemsFor(t, registryWith(absent)), "sources[0].quotas", "required and absent")

	stated := validSource()
	stated["quotas"] = "unknown"
	assertNoProblems(t, problemsFor(t, registryWith(stated)))
}

func TestAMisspelledFieldIsRefused(t *testing.T) {
	s := validSource()
	delete(s, "quotas")
	s["quota"] = "unknown"
	problems := problemsFor(t, registryWith(s))
	assertProblem(t, problems, "sources[0].quota", "not a field in the schema")
	assertProblem(t, problems, "sources[0].quotas", "required and absent")
}

func TestAnEmptyStringIsRefusedWhereUnknownIsTheAnswer(t *testing.T) {
	s := validSource()
	s["retention"] = "   "
	assertProblem(t, problemsFor(t, registryWith(s)), "sources[0].retention", "write `unknown`")
}

// --- closed vocabularies ------------------------------------------------------

func TestAnInventedDispositionIsRefused(t *testing.T) {
	s := validSource()
	s["access_status"] = "probably-fine"
	assertProblem(t, problemsFor(t, registryWith(s)), "sources[0].access_status", "permitted values are")
}

func TestVocabulariesAreClosed(t *testing.T) {
	for field, bad := range map[string]string{
		"kind":                 "rss",
		"authentication":       "oauth",
		"commercial_use":       "probably",
		"caching":              "sure",
		"redistribution":       "maybe",
		"attribution_required": "sometimes",
		"access_status":        "fine",
	} {
		t.Run(field, func(t *testing.T) {
			s := validSource()
			s[field] = bad
			assertProblem(t, problemsFor(t, registryWith(s)), "sources[0]."+field, "permitted values are")
		})
	}
}

// --- identity -----------------------------------------------------------------

func TestASourceIDIsNeverReusedWithinTheFile(t *testing.T) {
	a, b := validSource(), validSource()
	b["catalog_ref"] = "2"
	assertProblem(t, problemsFor(t, registryWith(a, b)), "sources[1].source_id", "ids are never reused")
}

func TestARetiredSourceIDCannotBeTakenAgain(t *testing.T) {
	// The rule docs/SOURCE_REGISTRY.md states — "never reused, never
	// renumbered" — cannot be enforced by looking at the current file alone,
	// because an id deleted in one commit is free in the next. The retired list
	// is what makes it checkable, and this is the case that proves the list is
	// consulted.
	b, err := json.Marshal(map[string]any{
		"schema_version":     1,
		"note":               "test fixture",
		"retired_source_ids": []any{"src-0001"},
		"sources":            []map[string]any{validSource()},
	})
	if err != nil {
		t.Fatal(err)
	}
	assertProblem(t, problemsFor(t, b), "sources[0].source_id", "retired id is never reused")
}

func TestTwoRecordsCannotClaimTheSameCatalogEntry(t *testing.T) {
	a, b := validSource(), validSource()
	b["source_id"] = "src-0002"
	assertProblem(t, problemsFor(t, registryWith(a, b)), "sources[1].catalog_ref", "already claimed")
}

func TestCatalogRefIsAnEntryNumberOrNone(t *testing.T) {
	s := validSource()
	s["catalog_ref"] = "wave one"
	assertProblem(t, problemsFor(t, registryWith(s)), "sources[0].catalog_ref", "positive entry number")

	none := validSource()
	none["catalog_ref"] = "none"
	assertNoProblems(t, problemsFor(t, registryWith(none)))
}

// --- a dated claim, or no claim ----------------------------------------------

func TestAResearchedRecordMustCarryTheDateItsDocumentationWasRead(t *testing.T) {
	s := validSource()
	s["verified_on"] = "unknown"
	assertProblem(t, problemsFor(t, registryWith(s)), "sources[0].verified_on", "states nothing current")
}

func TestAnUnresolvedRecordMayBeUndated(t *testing.T) {
	// `unresolved` means nobody has looked. Requiring a date there would force
	// an author to invent one, which is the opposite of the intent.
	s := validSource()
	s["access_status"] = "unresolved"
	s["verified_on"] = "unknown"
	s["official_documentation"] = "unknown"
	s["disposition_reason"] = "not yet researched"
	s["enabled"] = false
	assertNoProblems(t, problemsFor(t, registryWith(s)))
}

func TestAFutureVerificationDateIsRefused(t *testing.T) {
	s := validSource()
	s["verified_on"] = "2026-09-09"
	assertProblem(t, problemsFor(t, registryWith(s)), "sources[0].verified_on", "in the future")
}

func TestAMalformedDateIsRefused(t *testing.T) {
	s := validSource()
	s["verified_on"] = "September 2026"
	assertProblem(t, problemsFor(t, registryWith(s)), "sources[0].verified_on", "must be a date")
}

func TestAResearchedRecordMustNameTheDocumentationItWasReadFrom(t *testing.T) {
	s := validSource()
	s["official_documentation"] = "unknown"
	assertProblem(t, problemsFor(t, registryWith(s)), "sources[0].official_documentation", "record the URL")
}

func TestDocumentationReadOverPlaintextIsRefused(t *testing.T) {
	s := validSource()
	s["official_documentation"] = "http://example.org/docs/feed"
	assertProblem(t, problemsFor(t, registryWith(s)), "sources[0].official_documentation", "must be fetched over https")
}

func TestARelativeDocumentationReferenceIsRefused(t *testing.T) {
	s := validSource()
	s["official_documentation"] = "docs/feed"
	assertProblem(t, problemsFor(t, registryWith(s)), "sources[0].official_documentation", "not an absolute URL")
}

// --- enabling is a separate decision -----------------------------------------

func TestEnablingRequiresAVerifiedAvailableDisposition(t *testing.T) {
	for _, status := range []string{
		"credentials-required", "commercial-approval-required",
		"historical", "unavailable", "unresolved",
	} {
		t.Run(status, func(t *testing.T) {
			s := validSource()
			s["access_status"] = status
			s["enabled"] = true
			assertProblem(t, problemsFor(t, registryWith(s)), "sources[0].enabled", "only `verified-available` may be enabled")
		})
	}
}

func TestEnablingRequiresRightsThatPermitTheUse(t *testing.T) {
	for _, field := range []string{"commercial_use", "caching", "redistribution"} {
		for _, value := range []string{"prohibited", "unknown"} {
			t.Run(field+"/"+value, func(t *testing.T) {
				s := validSource()
				s[field] = value
				s["enabled"] = true
				assertProblem(t, problemsFor(t, registryWith(s)), "sources[0].enabled", "prohibited or unknown")
			})
		}
	}
}

func TestAFullyQualifiedSourceMayBeEnabled(t *testing.T) {
	// The positive control. Without it, every case above would pass against a
	// validator that simply refused to enable anything.
	s := validSource()
	s["redistribution"] = "conditional"
	s["enabled"] = true
	assertNoProblems(t, problemsFor(t, registryWith(s)))
}

// --- independence -------------------------------------------------------------

func TestADependencyMustNameARecordThatExists(t *testing.T) {
	s := validSource()
	s["aggregation_dependencies"] = []any{"src-9999"}
	assertProblem(t, problemsFor(t, registryWith(s)), "sources[0].aggregation_dependencies[0]", "not a source_id in this registry")
}

func TestARecordCannotDependOnItself(t *testing.T) {
	s := validSource()
	s["aggregation_dependencies"] = []any{"src-0001"}
	assertProblem(t, problemsFor(t, registryWith(s)), "sources[0].aggregation_dependencies[0]", "names its own record")
}

func TestADeclaredSharedUpstreamIsAccepted(t *testing.T) {
	a := validSource()
	b := validSource()
	b["source_id"] = "src-0002"
	b["catalog_ref"] = "2"
	b["aggregation_dependencies"] = []any{"src-0001"}
	assertNoProblems(t, problemsFor(t, registryWith(a, b)))
}

func TestIndicatorTypesMustSaySomething(t *testing.T) {
	s := validSource()
	s["indicator_types"] = []any{}
	assertProblem(t, problemsFor(t, registryWith(s)), "sources[0].indicator_types", "or [\"unknown\"]")
}

// --- file-level ---------------------------------------------------------------

func TestAnUnknownSchemaVersionIsRefused(t *testing.T) {
	b, err := json.Marshal(map[string]any{
		"schema_version":     2,
		"note":               "test fixture",
		"retired_source_ids": []any{},
		"sources":            []any{},
	})
	if err != nil {
		t.Fatal(err)
	}
	assertProblem(t, problemsFor(t, b), "schema_version", "refuses to guess")
}

func TestTopLevelKeysAreRequired(t *testing.T) {
	for _, key := range []string{"schema_version", "note", "retired_source_ids", "sources"} {
		t.Run(key, func(t *testing.T) {
			full := map[string]any{
				"schema_version":     1,
				"note":               "test fixture",
				"retired_source_ids": []any{},
				"sources":            []any{},
			}
			delete(full, key)
			b, err := json.Marshal(full)
			if err != nil {
				t.Fatal(err)
			}
			assertProblem(t, problemsFor(t, b), key, "required and absent")
		})
	}
}

func TestMalformedJSONIsAParseFailureNotAValidationFailure(t *testing.T) {
	// Two different facts. A caller that conflates them cannot tell "this file
	// is not JSON" from "this file is JSON and says something impossible".
	if _, _, err := Parse([]byte("{ not json")); err == nil {
		t.Fatal("expected a parse error")
	}
}

// --- the shipped registry -----------------------------------------------------

func TestTheShippedRegistryIsValid(t *testing.T) {
	// The file this repository actually carries, checked against the clock, so
	// a record with a future date cannot be committed.
	path := filepath.Join("..", "..", "docs", "source-registry.json")
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("the shipped registry is missing: %v", err)
	}
	reg, parseProblems, err := Load(path)
	if err != nil {
		t.Fatalf("the shipped registry did not parse: %v", err)
	}
	problems := append(parseProblems, reg.Validate(time.Now())...)
	if len(problems) != 0 {
		t.Fatalf("the shipped registry does not validate:\n%s", render(problems))
	}
}

func TestTheShippedRegistryEnablesNothing(t *testing.T) {
	// ORDER 2 has qualified no source. A record that turned up here with
	// `enabled: true` would be a source switched on without a qualification
	// this project has not performed, and that must fail loudly rather than be
	// noticed later.
	reg, _, err := Load(filepath.Join("..", "..", "docs", "source-registry.json"))
	if err != nil {
		t.Fatalf("the shipped registry did not parse: %v", err)
	}
	for i, s := range reg.Sources {
		if s.Enabled != nil && *s.Enabled {
			t.Errorf("sources[%d] (%s) is enabled; no source has been qualified", i, s.SourceID)
		}
		if s.AccessStatus == "verified-available" {
			t.Errorf("sources[%d] (%s) claims verified-available; no provider documentation has been read", i, s.SourceID)
		}
	}
}
