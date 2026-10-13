package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Sub is one subreddit the drafter is allowed to draft for.
type Sub struct {
	Name string `json:"name"`
	For  string `json:"for"`
}

// Config is the drafter's config file. Nothing here is specific to one
// person or one machine; every path and value comes from the file at
// -config (default ~/.config/lurker-drafter/config.json).
type Config struct {
	InboxURL  string   `json:"inbox_url"`
	TokenEnv  string   `json:"token_env"`
	Claude    []string `json:"claude"`
	VoiceFile string   `json:"voice_file"`
	Subs      []Sub    `json:"subs"`
}

// LoadConfig reads and validates a config file, expanding a leading ~ in
// voice_file to the user's home directory.
func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(expandHome(path))
	if err != nil {
		return nil, fmt.Errorf("read config %s: %w", path, err)
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse config %s: %w", path, err)
	}
	if cfg.InboxURL == "" {
		return nil, fmt.Errorf("config %s: inbox_url is required", path)
	}
	if cfg.TokenEnv == "" {
		cfg.TokenEnv = "DRAFTER_TOKEN"
	}
	if len(cfg.Claude) == 0 {
		cfg.Claude = []string{"claude", "-p", "--model", "sonnet"}
	}
	if len(cfg.Subs) == 0 {
		return nil, fmt.Errorf("config %s: subs must list at least one subreddit", path)
	}
	cfg.VoiceFile = expandHome(cfg.VoiceFile)
	cfg.InboxURL = strings.TrimRight(cfg.InboxURL, "/")
	return &cfg, nil
}

func expandHome(path string) string {
	if path == "" || !strings.HasPrefix(path, "~") {
		return path
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return path
	}
	if path == "~" {
		return home
	}
	if strings.HasPrefix(path, "~/") {
		return filepath.Join(home, path[2:])
	}
	return path
}

// SubNames returns the set of configured subreddit names.
func (c *Config) SubNames() map[string]bool {
	out := make(map[string]bool, len(c.Subs))
	for _, s := range c.Subs {
		out[s.Name] = true
	}
	return out
}
