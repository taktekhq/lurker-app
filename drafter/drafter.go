package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Drafter is the core orchestrator: claim a share, download its photos,
// build the prompt, run claude, gate the result, and report back.
type Drafter struct {
	Config    *Config
	Client    *InboxClient
	RunClaude ClaudeFunc
}

// RunLoop claims and processes shares forever, polling every interval when
// there is nothing to do. It returns when ctx is cancelled.
func (d *Drafter) RunLoop(ctx context.Context, interval time.Duration) {
	for {
		if ctx.Err() != nil {
			return
		}
		did, err := d.ProcessOne(ctx)
		if err != nil {
			log.Printf("process: %v", err)
		}
		if did {
			continue
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(interval):
		}
	}
}

// ProcessOne claims at most one share and handles it. The bool return says
// whether a share was claimed (true) or the inbox was empty (false),
// regardless of whether handling it then failed.
func (d *Drafter) ProcessOne(ctx context.Context) (bool, error) {
	share, err := d.Client.Claim()
	if err != nil {
		return false, fmt.Errorf("claim: %w", err)
	}
	if share == nil {
		return false, nil
	}

	if err := d.handle(share); err != nil {
		return true, err
	}
	return true, nil
}

func (d *Drafter) handle(share *Share) error {
	tempDir, err := os.MkdirTemp("", "lurker-drafter-")
	if err != nil {
		return d.fail(share.ID, fmt.Sprintf("create temp dir: %v", err))
	}
	defer os.RemoveAll(tempDir)

	photoPaths := make([]string, 0, len(share.Photos))
	for i, key := range share.Photos {
		data, err := d.Client.GetPhoto(key)
		if err != nil {
			return d.fail(share.ID, fmt.Sprintf("download photo %s: %v", key, err))
		}
		path := filepath.Join(tempDir, fmt.Sprintf("%d.jpg", i))
		if err := os.WriteFile(path, data, 0o600); err != nil {
			return d.fail(share.ID, fmt.Sprintf("save photo: %v", err))
		}
		photoPaths = append(photoPaths, path)
	}

	rules, err := d.Client.GetRules()
	if err != nil {
		return d.fail(share.ID, fmt.Sprintf("get rules: %v", err))
	}

	voice, err := os.ReadFile(d.Config.VoiceFile)
	if err != nil {
		return d.fail(share.ID, fmt.Sprintf("read voice file: %v", err))
	}

	prompt := BuildPrompt(d.Config, rules, string(voice), share.Note, photoPaths)

	args := make([]string, 0, len(d.Config.Claude)+9)
	args = append(args, d.Config.Claude...)
	args = append(args,
		"--strict-mcp-config",
		"--mcp-config", `{"mcpServers":{}}`,
		"--allowedTools", "Read",
		"--output-format", "json",
		"--add-dir", tempDir,
		prompt,
	)

	rawOut, err := d.RunClaude(args)
	if err != nil {
		return d.fail(share.ID, fmt.Sprintf("claude: %v", err))
	}

	drafts, presence, err := ParseModelDrafts(rawOut)
	if err != nil {
		return d.fail(share.ID, fmt.Sprintf("parse model output: %v", err))
	}
	if len(drafts) == 0 {
		return d.fail(share.ID, "model returned no drafts")
	}
	if len(drafts) > 3 {
		drafts = drafts[:3]
		presence = presence[:3]
	}

	kept := make([]Draft, 0, len(drafts))
	reasons := make([]string, 0, len(drafts))
	for i, draft := range drafts {
		fixed, reason := applyGates(draft, presence[i], d.Config, rules)
		if reason != "" {
			reasons = append(reasons, fmt.Sprintf("%s: %s", draft.Sub, reason))
			continue
		}
		kept = append(kept, fixed)
	}

	if len(kept) == 0 {
		return d.fail(share.ID, strings.Join(reasons, "; "))
	}

	if err := d.Client.PostDrafts(share.ID, kept); err != nil {
		return fmt.Errorf("post drafts: %w", err)
	}
	return nil
}

func (d *Drafter) fail(id string, reason string) error {
	if err := d.Client.PostFailed(id, reason); err != nil {
		return fmt.Errorf("%s (also failed to report failure: %v)", reason, err)
	}
	return errors.New(reason)
}
