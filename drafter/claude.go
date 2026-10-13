package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// ClaudeFunc runs the claude CLI with the given full argument list (the
// configured base command plus the fixed flags and the prompt) and returns
// its raw stdout. Tests inject a fake instead of RunClaudeCLI.
type ClaudeFunc func(args []string) (string, error)

// RunClaudeCLI is the real implementation, used outside of tests.
func RunClaudeCLI(args []string) (string, error) {
	if len(args) == 0 {
		return "", fmt.Errorf("no claude command configured")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, args[0], args[1:]...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("%w: %s", err, strings.TrimSpace(stderr.String()))
	}
	return stdout.String(), nil
}

// ExtractResultText pulls the "result" field out of the claude CLI's
// --output-format json envelope, which holds the model's final text reply.
func ExtractResultText(envelope string) (string, error) {
	var parsed struct {
		Result string `json:"result"`
	}
	if err := json.Unmarshal([]byte(envelope), &parsed); err != nil {
		return "", fmt.Errorf("parse claude envelope: %w", err)
	}
	if strings.TrimSpace(parsed.Result) == "" {
		return "", fmt.Errorf("claude envelope has no result field")
	}
	return parsed.Result, nil
}

// ExtractJSONObject finds the first balanced {...} object in text, which
// the model may wrap in prose or a markdown code fence.
func ExtractJSONObject(text string) (string, error) {
	start := strings.IndexByte(text, '{')
	if start < 0 {
		return "", fmt.Errorf("no JSON object found in model output")
	}
	depth := 0
	inString := false
	escaped := false
	for i := start; i < len(text); i++ {
		c := text[i]
		if inString {
			switch {
			case escaped:
				escaped = false
			case c == '\\':
				escaped = true
			case c == '"':
				inString = false
			}
			continue
		}
		switch c {
		case '"':
			inString = true
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return text[start : i+1], nil
			}
		}
	}
	return "", fmt.Errorf("unbalanced JSON object in model output")
}

type modelResponse struct {
	Drafts []map[string]interface{} `json:"drafts"`
}

// ParseModelDrafts turns the raw claude CLI stdout into Drafts, plus a
// parallel slice saying whether each draft included both fact fields
// (facts_from_note and facts_from_photo), which applyGates needs to know
// before it can trust the rest of the draft.
func ParseModelDrafts(rawOut string) ([]Draft, []bool, error) {
	resultText, err := ExtractResultText(rawOut)
	if err != nil {
		return nil, nil, err
	}
	obj, err := ExtractJSONObject(resultText)
	if err != nil {
		return nil, nil, err
	}
	var parsed modelResponse
	if err := json.Unmarshal([]byte(obj), &parsed); err != nil {
		return nil, nil, fmt.Errorf("parse drafts JSON: %w", err)
	}

	drafts := make([]Draft, 0, len(parsed.Drafts))
	presence := make([]bool, 0, len(parsed.Drafts))
	for _, raw := range parsed.Drafts {
		_, hasNote := raw["facts_from_note"]
		_, hasPhoto := raw["facts_from_photo"]

		encoded, err := json.Marshal(raw)
		if err != nil {
			return nil, nil, err
		}
		var d Draft
		if err := json.Unmarshal(encoded, &d); err != nil {
			return nil, nil, err
		}
		drafts = append(drafts, d)
		presence = append(presence, hasNote && hasPhoto)
	}
	return drafts, presence, nil
}
