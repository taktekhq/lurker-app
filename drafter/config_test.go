package main

import (
	"os"
	"path/filepath"
	"testing"
)

func writeTempConfig(t *testing.T, contents string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "config.json")
	if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLoadConfigFillsDefaults(t *testing.T) {
	path := writeTempConfig(t, `{
		"inbox_url": "https://example.workers.dev/",
		"voice_file": "voice.md",
		"subs": [{"name": "Ducati", "for": "his bike"}]
	}`)

	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.TokenEnv != "DRAFTER_TOKEN" {
		t.Errorf("token_env default = %q, want DRAFTER_TOKEN", cfg.TokenEnv)
	}
	if len(cfg.Claude) == 0 {
		t.Error("claude command default should not be empty")
	}
	if cfg.InboxURL != "https://example.workers.dev" {
		t.Errorf("inbox_url = %q, want trailing slash trimmed", cfg.InboxURL)
	}
}

func TestLoadConfigRequiresInboxURL(t *testing.T) {
	path := writeTempConfig(t, `{"subs": [{"name": "Ducati", "for": "his bike"}]}`)
	if _, err := LoadConfig(path); err == nil {
		t.Fatal("expected an error for a missing inbox_url")
	}
}

func TestLoadConfigRequiresSubs(t *testing.T) {
	path := writeTempConfig(t, `{"inbox_url": "https://example.workers.dev"}`)
	if _, err := LoadConfig(path); err == nil {
		t.Fatal("expected an error for an empty subs list")
	}
}

func TestExpandHome(t *testing.T) {
	home, err := os.UserHomeDir()
	if err != nil {
		t.Skip("no home dir in this environment")
	}
	if got := expandHome("~/x/y.md"); got != filepath.Join(home, "x", "y.md") {
		t.Errorf("expandHome(~/x/y.md) = %q", got)
	}
	if got := expandHome("/abs/path"); got != "/abs/path" {
		t.Errorf("expandHome should leave absolute paths alone, got %q", got)
	}
}

func TestSubNames(t *testing.T) {
	cfg := &Config{Subs: []Sub{{Name: "Ducati"}, {Name: "motorcycles"}}}
	names := cfg.SubNames()
	if !names["Ducati"] || !names["motorcycles"] || names["pics"] {
		t.Errorf("SubNames() = %v", names)
	}
}
