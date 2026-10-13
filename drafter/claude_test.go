package main

import (
	"strings"
	"testing"
)

func TestExtractResultText(t *testing.T) {
	envelope := `{"type":"result","subtype":"success","result":"here you go: {\"drafts\":[]}"}`
	text, err := ExtractResultText(envelope)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(text, "drafts") {
		t.Errorf("got %q", text)
	}
}

func TestExtractResultTextRejectsEmptyResult(t *testing.T) {
	if _, err := ExtractResultText(`{"result": ""}`); err == nil {
		t.Fatal("expected an error for an empty result")
	}
}

func TestExtractResultTextRejectsBadJSON(t *testing.T) {
	if _, err := ExtractResultText(`not json`); err == nil {
		t.Fatal("expected an error for invalid JSON")
	}
}

func TestExtractJSONObjectPlain(t *testing.T) {
	obj, err := ExtractJSONObject(`{"a": 1}`)
	if err != nil {
		t.Fatal(err)
	}
	if obj != `{"a": 1}` {
		t.Errorf("got %q", obj)
	}
}

func TestExtractJSONObjectWithSurroundingProse(t *testing.T) {
	text := "Sure, here are the drafts:\n```json\n{\"drafts\": [{\"title\": \"a}b\"}]}\n```\nHope that helps!"
	obj, err := ExtractJSONObject(text)
	if err != nil {
		t.Fatal(err)
	}
	if obj != `{"drafts": [{"title": "a}b"}]}` {
		t.Errorf("got %q", obj)
	}
}

func TestExtractJSONObjectNested(t *testing.T) {
	text := `prefix {"a": {"b": {"c": 1}}} suffix`
	obj, err := ExtractJSONObject(text)
	if err != nil {
		t.Fatal(err)
	}
	if obj != `{"a": {"b": {"c": 1}}}` {
		t.Errorf("got %q", obj)
	}
}

func TestExtractJSONObjectNoObject(t *testing.T) {
	if _, err := ExtractJSONObject("no braces here"); err == nil {
		t.Fatal("expected an error")
	}
}

func TestParseModelDraftsFullRoundTrip(t *testing.T) {
	modelJSON := `{"drafts": [` +
		`{"sub": "Ducati", "title": "morning ride", "body": "", "why": "his bike", "rule_notes": "", "facts_from_note": ["rode this morning"], "facts_from_photo": []},` +
		`{"sub": "motorcycles", "title": "no facts fields"}` +
		`]}`
	envelope := `{"result": "here: ` + jsonEscape(modelJSON) + `"}`

	drafts, presence, err := ParseModelDrafts(envelope)
	if err != nil {
		t.Fatal(err)
	}
	if len(drafts) != 2 {
		t.Fatalf("got %d drafts", len(drafts))
	}
	if drafts[0].Sub != "Ducati" || drafts[0].Title != "morning ride" {
		t.Errorf("draft 0 = %+v", drafts[0])
	}
	if !presence[0] {
		t.Error("draft 0 should have both fact fields present")
	}
	if presence[1] {
		t.Error("draft 1 is missing fact fields and should not be marked present")
	}
}

func TestParseModelDraftsRejectsUnparsableResult(t *testing.T) {
	envelope := `{"result": "no json object in here"}`
	if _, _, err := ParseModelDrafts(envelope); err == nil {
		t.Fatal("expected an error")
	}
}

// jsonEscape escapes a string for embedding inside a JSON string literal
// in these tests' hand-built envelopes.
func jsonEscape(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch r {
		case '"':
			b.WriteString(`\"`)
		case '\\':
			b.WriteString(`\\`)
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}
