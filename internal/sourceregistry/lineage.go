// SPDX-License-Identifier: AGPL-3.0-only

package sourceregistry

import (
	"fmt"
	"sort"
	"strings"
)

// Upstream-completeness vocabulary.
//
// docs/SOURCE_REGISTRY.md offers `aggregation_dependencies` as the thing that
// "stops three feeds being counted as three independent sources". It does that
// only for dependencies somebody recorded. The field below records how much is
// known about the upstreams at all, which is the difference between "this
// source aggregates nothing" and "nobody has established what it aggregates".
//
// An unknown upstream is not demonstrated independence. Treating it as such is
// how three feeds sharing one upstream get counted as three.
const (
	// UpstreamDocumentedComplete — the provider documents its upstreams and
	// the record reflects all of them.
	UpstreamDocumentedComplete = "documented_complete"
	// UpstreamDocumentedPartial — some upstreams are documented and the
	// provider does not claim the list is exhaustive.
	UpstreamDocumentedPartial = "documented_partial"
	// UpstreamUnknown — the provider does not say. The default, and the honest
	// answer for most aggregators.
	UpstreamUnknown = "unknown"
)

// ValidUpstreamCompleteness is the closed vocabulary.
var ValidUpstreamCompleteness = []string{
	UpstreamDocumentedComplete, UpstreamDocumentedPartial, UpstreamUnknown,
}

// IndependenceClaimable reports whether this source may be COUNTED as
// independent of the others, and why not when it may not.
//
// This is deliberately not a field an author can set. Independence is a
// property of what is known about lineage, and a record that says "independent"
// while its upstreams are undocumented is asserting the absence of evidence as
// evidence of absence.
//
// It is the gate for first-wave selection: a wave that wants N independent
// sources must satisfy this for each of them, or say plainly that it is
// choosing sources whose independence is unestablished.
func (s *Source) IndependenceClaimable() (bool, string) {
	switch s.UpstreamSourcesCompleteness {
	case UpstreamDocumentedComplete:
		return true, ""
	case UpstreamDocumentedPartial:
		return false, fmt.Sprintf(
			"%s documents its upstreams only partially, so an upstream shared with another registry entry may exist and be unrecorded",
			s.SourceID)
	case UpstreamUnknown:
		return false, fmt.Sprintf(
			"%s does not document its upstreams, so nothing is known about what it aggregates; an unknown upstream is not demonstrated independence",
			s.SourceID)
	default:
		return false, fmt.Sprintf("%s carries an unrecognised upstream_sources_completeness %q", s.SourceID, s.UpstreamSourcesCompleteness)
	}
}

// validateLineage checks the dependency graph as a graph.
//
// aggregation_dependencies is a LINEAGE edge: "this source's records are drawn,
// in whole or in part, from that source". It is not a general relatedness link,
// and it is not the place to record that two sources happen to cover the same
// sector or that one is a good cross-check for another. Lineage has to stay
// lineage, because the deduplication and independence reasoning that will
// eventually read this graph is only correct if every edge means the same
// thing.
//
// A cycle in lineage is therefore a contradiction rather than a curiosity: A
// cannot be derived from B while B is derived from A. Where two aggregators
// genuinely exchange data in both directions, that is a shared-upstream
// relationship to be recorded on both records, not a loop.
func (r *Registry) validateLineage(problems *[]Problem) {
	index := map[string]int{}
	for i, s := range r.Sources {
		if _, dup := index[s.SourceID]; !dup {
			index[s.SourceID] = i
		}
	}

	for i := range r.Sources {
		s := &r.Sources[i]
		at := func(f string) string { return fmt.Sprintf("sources[%d].%s", i, f) }

		if !contains(ValidUpstreamCompleteness, s.UpstreamSourcesCompleteness) {
			*problems = append(*problems, Problem{
				at("upstream_sources_completeness"),
				fmt.Sprintf("is %q; permitted values are %s", s.UpstreamSourcesCompleteness, strings.Join(ValidUpstreamCompleteness, ", ")),
			})
		}

		// A record claiming complete upstream documentation while listing no
		// upstreams is making a strong claim — "this source aggregates nothing"
		// — and it is a legitimate one for a primary observer. It is only
		// refused when it contradicts the lineage edges the same record
		// carries.
		if s.UpstreamSourcesCompleteness == UpstreamDocumentedComplete &&
			len(s.UpstreamSources) == 0 && len(s.AggregationDependencies) > 0 {
			*problems = append(*problems, Problem{
				at("upstream_sources"),
				"is empty and upstream_sources_completeness is `documented_complete`, but aggregation_dependencies names registry entries this source draws from — the two statements contradict each other",
			})
		}

		seen := map[string]bool{}
		for j, dep := range s.AggregationDependencies {
			p := at(fmt.Sprintf("aggregation_dependencies[%d]", j))
			switch {
			case strings.TrimSpace(dep) == "":
				*problems = append(*problems, Problem{p, "is empty"})
			case dep == s.SourceID:
				*problems = append(*problems, Problem{
					p,
					"names its own record; a source cannot be an upstream of itself, and a self-edge would make every downstream independence calculation wrong",
				})
			case seen[dep]:
				*problems = append(*problems, Problem{p, fmt.Sprintf("names %q twice", dep)})
			default:
				if _, ok := index[dep]; !ok {
					*problems = append(*problems, Problem{
						p,
						fmt.Sprintf("names %q, which is not a source_id in this registry; a lineage edge to a record that does not exist establishes nothing", dep),
					})
				}
			}
			seen[dep] = true
		}
	}

	for _, cycle := range r.dependencyCycles() {
		*problems = append(*problems, Problem{
			"sources." + cycle[0] + ".aggregation_dependencies",
			fmt.Sprintf("takes part in a lineage cycle: %s. Lineage is directional — a source cannot be derived from something that is derived from it — so this is a contradiction, not a loop to be broken arbitrarily", strings.Join(cycle, " -> ")),
		})
	}
}

// dependencyCycles finds every cycle in the lineage graph, each reported once,
// canonicalised so that the same cycle is not reported from several starting
// points.
func (r *Registry) dependencyCycles() [][]string {
	adj := map[string][]string{}
	for _, s := range r.Sources {
		adj[s.SourceID] = append(adj[s.SourceID], s.AggregationDependencies...)
	}

	const (
		white = 0 // unvisited
		grey  = 1 // on the current path
		black = 2 // finished
	)
	colour := map[string]int{}
	var path []string
	found := map[string][]string{}

	var visit func(string)
	visit = func(n string) {
		colour[n] = grey
		path = append(path, n)
		for _, m := range adj[n] {
			if _, known := adj[m]; !known {
				continue // dangling edge; reported separately
			}
			switch colour[m] {
			case white:
				visit(m)
			case grey:
				// Cycle: from m's position on the current path, back to m.
				start := 0
				for k, p := range path {
					if p == m {
						start = k
						break
					}
				}
				cycle := append([]string{}, path[start:]...)
				cycle = append(cycle, m)
				found[canonicalCycle(cycle)] = cycle
			}
		}
		path = path[:len(path)-1]
		colour[n] = black
	}

	ids := make([]string, 0, len(adj))
	for id := range adj {
		ids = append(ids, id)
	}
	sort.Strings(ids) // deterministic reporting
	for _, id := range ids {
		if colour[id] == white {
			visit(id)
		}
	}

	keys := make([]string, 0, len(found))
	for k := range found {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	out := make([][]string, 0, len(keys))
	for _, k := range keys {
		out = append(out, found[k])
	}
	return out
}

// canonicalCycle gives a cycle a single name regardless of where the walk
// entered it, so A->B->A and B->A->B are one finding rather than two.
func canonicalCycle(cycle []string) string {
	nodes := append([]string{}, cycle[:len(cycle)-1]...)
	sort.Strings(nodes)
	return strings.Join(nodes, "|")
}
