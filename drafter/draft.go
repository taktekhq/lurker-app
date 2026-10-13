package main

// Draft mirrors the Draft shape from SPEC.md, plus the two fact-grounding
// fields the prompt requires the model to fill in.
type Draft struct {
	Sub            string   `json:"sub"`
	Title          string   `json:"title"`
	Body           string   `json:"body"`
	Why            string   `json:"why"`
	RulesChecked   bool     `json:"rules_checked"`
	RuleNotes      string   `json:"rule_notes"`
	FactsFromNote  []string `json:"facts_from_note"`
	FactsFromPhoto []string `json:"facts_from_photo"`
}
