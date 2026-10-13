package main

import (
	"fmt"
	"strings"
)

// BuildPrompt assembles the prompt sent to claude: the subs list with
// "for" lines, the cached rules per sub, the voice file text, and the
// note, plus the hard rules from SPEC.md.
func BuildPrompt(cfg *Config, rules map[string][]string, voice string, note string, photoPaths []string) string {
	var b strings.Builder

	b.WriteString("You draft Reddit post titles and bodies for photos someone shares from ")
	b.WriteString("their phone. You never post anything yourself, you only draft.\n\n")

	b.WriteString("Subreddits you may use, and what each is for:\n")
	for _, s := range cfg.Subs {
		fmt.Fprintf(&b, "- %s: for %s\n", s.Name, s.For)
	}
	b.WriteString("\n")

	hasRules := false
	for _, s := range cfg.Subs {
		subRules, ok := rules[s.Name]
		if !ok || len(subRules) == 0 {
			continue
		}
		if !hasRules {
			b.WriteString("Rules for these subreddits, follow them:\n")
			hasRules = true
		}
		fmt.Fprintf(&b, "%s:\n", s.Name)
		for _, r := range subRules {
			fmt.Fprintf(&b, "- %s\n", r)
		}
	}
	if hasRules {
		b.WriteString("\n")
	}

	if strings.TrimSpace(voice) != "" {
		b.WriteString("Write in this voice:\n")
		b.WriteString(voice)
		b.WriteString("\n\n")
	}

	if strings.TrimSpace(note) != "" {
		fmt.Fprintf(&b, "Note from the person sharing these photos: %s\n\n", note)
	} else {
		b.WriteString("There is no note from the person sharing these photos.\n\n")
	}

	b.WriteString("Photos, read them with your Read tool:\n")
	for _, p := range photoPaths {
		fmt.Fprintf(&b, "- %s\n", p)
	}
	b.WriteString("\n")

	b.WriteString("Hard rules:\n")
	b.WriteString("- Use only facts visible in the photos or written in the note. Never invent a place, date, name, number or event.\n")
	b.WriteString("- For each draft, list facts_from_note (facts you took from the note) and facts_from_photo (facts you took from the photos). Both can be empty arrays, but both must be present in every draft.\n")
	b.WriteString("- Titles must be plain and casual, the way an ordinary person titles their own photo. No marketing language, no links, and nothing about any company or project the person runs.\n")
	b.WriteString("- Never use an em dash or an en dash in the title or body. Use a full stop or a comma instead.\n\n")

	b.WriteString("Reply with strict JSON only, no prose before or after, of this exact shape:\n")
	b.WriteString(`{"drafts": [{"sub": "...", "title": "...", "body": "", "why": "one line: why this sub", "rule_notes": "...", "facts_from_note": [], "facts_from_photo": []}]}`)
	b.WriteString("\n")
	b.WriteString("Give 1 to 3 drafts, each for a different subreddit from the list above.\n")

	return b.String()
}
