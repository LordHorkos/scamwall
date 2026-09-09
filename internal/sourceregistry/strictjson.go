// SPDX-License-Identifier: AGPL-3.0-only

package sourceregistry

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"strings"
)

// MaxRegistryBytes caps the input this package will consider.
//
// The registry is a hand-maintained document of at most a few hundred records.
// A file larger than this is not a big registry; it is a mistake or a hostile
// input, and refusing it costs nothing a legitimate author would notice. The
// limit exists because "parse whatever arrives" is how a parser becomes a
// denial-of-service surface, and because docs/SOURCE_REGISTRY.md §4 says
// downloaded records are untrusted input — the registry itself is no more
// trusted than the things it describes.
const MaxRegistryBytes = 8 << 20 // 8 MiB

// checkNoDuplicateKeys walks the raw JSON and refuses any object that names a
// key twice.
//
// # WHY THIS IS NOT LEFT TO THE DECODER
//
// encoding/json accepts duplicate keys and keeps the LAST one. That is not a
// parse error, it is a silent choice, and for this file it is the worst
// possible one: a record carrying
//
//	"commercial_use": "prohibited", ... "commercial_use": "permitted"
//
// decodes to `permitted` with no diagnostic. A reviewer reading the file sees
// the prohibition; the program sees the permission; both are reading the same
// bytes. Whichever way a decoder resolves that, resolving it at all is wrong
// here — the document is ambiguous and must be refused rather than
// interpreted.
//
// The walk is over tokens rather than a decoded value, because by the time a
// value exists the duplicate is already gone.
func checkNoDuplicateKeys(b []byte) []Problem {
	dec := json.NewDecoder(bytes.NewReader(b))
	dec.UseNumber()
	var problems []Problem
	walkForDuplicates(dec, "", &problems)
	return problems
}

// walkForDuplicates consumes exactly one JSON value from dec.
func walkForDuplicates(dec *json.Decoder, path string, problems *[]Problem) {
	tok, err := dec.Token()
	if err != nil {
		// Malformed JSON is reported by the decode that follows; this walk
		// only reports duplicates, and stops quietly when it can no longer
		// read. Reporting the same syntax error twice, in two vocabularies,
		// would make the real problem harder to find.
		return
	}
	delim, isDelim := tok.(json.Delim)
	if !isDelim {
		return // a scalar; nothing nested to check
	}
	switch delim {
	case '{':
		seen := map[string]bool{}
		for dec.More() {
			keyTok, err := dec.Token()
			if err != nil {
				return
			}
			key, ok := keyTok.(string)
			if !ok {
				return
			}
			here := key
			if path != "" {
				here = path + "." + key
			}
			if seen[key] {
				*problems = append(*problems, Problem{
					here,
					"appears twice in the same object — the document is ambiguous about its own contents and is refused rather than resolved to whichever value a decoder happens to keep",
				})
			}
			seen[key] = true
			walkForDuplicates(dec, here, problems)
		}
		_, _ = dec.Token() // consume '}'
	case '[':
		i := 0
		for dec.More() {
			walkForDuplicates(dec, fmt.Sprintf("%s[%d]", path, i), problems)
			i++
		}
		_, _ = dec.Token() // consume ']'
	}
}

// decodeStrict decodes one JSON document into v, refusing unknown fields and
// refusing trailing content after the value.
//
// Trailing content is checked because a decoder that reads the first value and
// stops will happily accept `{...}{...}`, taking the first object and silently
// discarding the second. For a document of record, "there was more here and it
// was ignored" is not an acceptable outcome.
func decodeStrict(b []byte, v any) error {
	dec := json.NewDecoder(bytes.NewReader(b))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return err
	}
	if _, err := dec.Token(); err != io.EOF {
		return fmt.Errorf("trailing content after the top-level object; a registry file holds exactly one document")
	}
	return nil
}

// typeName renders a raw JSON value's type for a diagnostic, so that a
// malformed field says what it actually is rather than repeating Go's
// unmarshalling vocabulary at a person editing JSON.
func typeName(raw json.RawMessage) string {
	s := strings.TrimSpace(string(raw))
	if s == "" {
		return "empty"
	}
	switch s[0] {
	case '{':
		return "an object"
	case '[':
		return "an array"
	case '"':
		return "a string"
	case 't', 'f':
		return "a boolean"
	case 'n':
		return "null"
	default:
		return "a number"
	}
}
