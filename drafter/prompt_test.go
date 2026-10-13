package main

import (
	"strings"
	"testing"
)

func TestBuildPromptIncludesSubsAndReasons(t *testing.T) {
	cfg := &Config{Subs: []Sub{{Name: "Ducati", For: "his bike, rides, parts"}}}
	prompt := BuildPrompt(cfg, nil, "", "", nil)
	if !strings.Contains(prompt, "Ducati") || !strings.Contains(prompt, "his bike, rides, parts") {
		t.Errorf("prompt missing sub info: %s", prompt)
	}
}

func TestBuildPromptOnlyIncludesRulesForConfiguredSubsWithCachedRules(t *testing.T) {
	cfg := &Config{Subs: []Sub{{Name: "Ducati", For: "bike"}, {Name: "motorcycles", For: "bikes"}}}
	rules := map[string][]string{"Ducati": {"be nice"}, "SideProject": {"off topic sub, should not leak in"}}
	prompt := BuildPrompt(cfg, rules, "", "", nil)
	if !strings.Contains(prompt, "be nice") {
		t.Error("expected Ducati's cached rule in the prompt")
	}
	if strings.Contains(prompt, "SideProject") {
		t.Error("rules for a sub not in the config must not appear")
	}
}

func TestBuildPromptIncludesVoiceAndNote(t *testing.T) {
	cfg := &Config{Subs: []Sub{{Name: "Ducati", For: "bike"}}}
	prompt := BuildPrompt(cfg, nil, "short, plain, lowercase-ish", "took the scrambler out", []string{"/tmp/0.jpg"})
	if !strings.Contains(prompt, "short, plain, lowercase-ish") {
		t.Error("expected voice text in the prompt")
	}
	if !strings.Contains(prompt, "took the scrambler out") {
		t.Error("expected the note text in the prompt")
	}
	if !strings.Contains(prompt, "/tmp/0.jpg") {
		t.Error("expected the photo path in the prompt")
	}
}

func TestBuildPromptSaysNoNoteWhenNoteIsEmpty(t *testing.T) {
	cfg := &Config{Subs: []Sub{{Name: "Ducati", For: "bike"}}}
	prompt := BuildPrompt(cfg, nil, "", "", nil)
	if !strings.Contains(prompt, "no note") {
		t.Errorf("expected a 'no note' statement, got: %s", prompt)
	}
}

func TestBuildPromptStatesHardRules(t *testing.T) {
	cfg := &Config{Subs: []Sub{{Name: "Ducati", For: "bike"}}}
	prompt := BuildPrompt(cfg, nil, "", "", nil)
	for _, want := range []string{"facts_from_note", "facts_from_photo", "em dash", "en dash"} {
		if !strings.Contains(prompt, want) {
			t.Errorf("prompt missing %q", want)
		}
	}
}
