package main

import "testing"

func testConfig() *Config {
	return &Config{Subs: []Sub{{Name: "Ducati", For: "his bike"}, {Name: "motorcycles", For: "bikes"}}}
}

func TestApplyGatesAccepts(t *testing.T) {
	d := Draft{Sub: "Ducati", Title: "took it out this morning", Body: "", FactsFromNote: []string{"rode this morning"}, FactsFromPhoto: []string{}}
	rules := map[string][]string{"Ducati": {"be nice"}}
	fixed, reason := applyGates(d, true, testConfig(), rules)
	if reason != "" {
		t.Fatalf("unexpected rejection: %s", reason)
	}
	if !fixed.RulesChecked {
		t.Error("rules_checked should be true when the sub has cached rules")
	}
}

func TestApplyGatesRulesCheckedFalseWithoutCachedRules(t *testing.T) {
	d := Draft{Sub: "Ducati", Title: "took it out", FactsFromNote: []string{}, FactsFromPhoto: []string{}}
	fixed, reason := applyGates(d, true, testConfig(), map[string][]string{})
	if reason != "" {
		t.Fatalf("unexpected rejection: %s", reason)
	}
	if fixed.RulesChecked {
		t.Error("rules_checked should be false when there are no cached rules for the sub")
	}
}

func TestApplyGatesIgnoresModelsOwnRulesChecked(t *testing.T) {
	d := Draft{Sub: "Ducati", Title: "x", RulesChecked: true, FactsFromNote: []string{}, FactsFromPhoto: []string{}}
	fixed, _ := applyGates(d, true, testConfig(), map[string][]string{})
	if fixed.RulesChecked {
		t.Error("the drafter must not trust the model's own rules_checked claim")
	}
}

func TestApplyGatesRejectsUnconfiguredSub(t *testing.T) {
	d := Draft{Sub: "not_a_real_sub", Title: "x", FactsFromNote: []string{}, FactsFromPhoto: []string{}}
	_, reason := applyGates(d, true, testConfig(), nil)
	if reason == "" {
		t.Fatal("expected a rejection for an unconfigured sub")
	}
}

func TestApplyGatesRejectsMissingFacts(t *testing.T) {
	d := Draft{Sub: "Ducati", Title: "x"}
	_, reason := applyGates(d, false, testConfig(), nil)
	if reason == "" {
		t.Fatal("expected a rejection when fact fields are missing")
	}
}

func TestApplyGatesRejectsEmDash(t *testing.T) {
	title := "morning ride " + string(rune(0x2014)) + " scrambler"
	d := Draft{Sub: "Ducati", Title: title, FactsFromNote: []string{}, FactsFromPhoto: []string{}}
	_, reason := applyGates(d, true, testConfig(), nil)
	if reason == "" {
		t.Fatal("expected a rejection for an em dash")
	}
}

func TestApplyGatesRejectsEnDash(t *testing.T) {
	body := "9am" + string(rune(0x2013)) + "1pm ride"
	d := Draft{Sub: "Ducati", Title: "x", Body: body, FactsFromNote: []string{}, FactsFromPhoto: []string{}}
	_, reason := applyGates(d, true, testConfig(), nil)
	if reason == "" {
		t.Fatal("expected a rejection for an en dash")
	}
}

func TestApplyGatesRejectsLongTitle(t *testing.T) {
	d := Draft{Sub: "Ducati", Title: stringOfLength(300), FactsFromNote: []string{}, FactsFromPhoto: []string{}}
	_, reason := applyGates(d, true, testConfig(), nil)
	if reason == "" {
		t.Fatal("expected a rejection for a title at the 300 char limit")
	}
}

func TestApplyGatesRejectsEmptyTitle(t *testing.T) {
	d := Draft{Sub: "Ducati", Title: "   ", FactsFromNote: []string{}, FactsFromPhoto: []string{}}
	_, reason := applyGates(d, true, testConfig(), nil)
	if reason == "" {
		t.Fatal("expected a rejection for an empty title")
	}
}

func stringOfLength(n int) string {
	b := make([]byte, n)
	for i := range b {
		b[i] = 'a'
	}
	return string(b)
}
