package main

import (
	"fmt"
	"strings"
)

const (
	// Rune code points, not the literal characters: U+2014 (em dash) and
	// U+2013 (en dash). Keeping them as code points means the source file
	// never contains either character itself.
	emDash rune = 0x2014
	enDash rune = 0x2013
	// maxTitleChars matches Reddit's own title limit.
	maxTitleChars = 300
)

// applyGates checks one model-produced draft against the hard rules from
// SPEC.md. hasFacts says whether the model included both facts_from_note
// and facts_from_photo keys (they may be empty arrays, but must be
// present). rulesMap is the cached /v1/rules response.
//
// On success it returns the draft with rules_checked set by this function
// (never trusting the model's own claim) and an empty reason. On failure
// it returns a non-empty reason and the draft should be dropped.
func applyGates(d Draft, hasFacts bool, cfg *Config, rulesMap map[string][]string) (Draft, string) {
	if !cfg.SubNames()[d.Sub] {
		return d, fmt.Sprintf("sub %q is not in the configured sub list", d.Sub)
	}
	if !hasFacts {
		return d, "draft is missing facts_from_note or facts_from_photo"
	}
	if containsDash(d.Title) || containsDash(d.Body) {
		return d, "title or body contains an em dash or en dash"
	}
	if len(d.Title) >= maxTitleChars {
		return d, fmt.Sprintf("title is %d chars, must be under %d", len(d.Title), maxTitleChars)
	}
	if strings.TrimSpace(d.Title) == "" {
		return d, "title is empty"
	}

	_, hasRules := rulesMap[d.Sub]
	d.RulesChecked = hasRules
	return d, ""
}

func containsDash(s string) bool {
	return strings.ContainsRune(s, emDash) || strings.ContainsRune(s, enDash)
}
