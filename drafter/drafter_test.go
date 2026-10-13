package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
)

var errFakeClaude = errors.New("claude binary not found")

// fakeWorker is a minimal stand-in for the lurker-app worker, just enough
// of SPEC.md's routes for the drafter to exercise against.
type fakeWorker struct {
	mu          sync.Mutex
	share       *Share
	photos      map[string][]byte
	rules       map[string][]string
	postedBody  map[string]interface{}
	postedCount int
}

func newFakeWorker() *fakeWorker {
	return &fakeWorker{photos: map[string][]byte{}, rules: map[string][]string{}}
}

func (f *fakeWorker) server() *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()

		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/v1/claim":
			if f.share == nil {
				w.WriteHeader(http.StatusNoContent)
				return
			}
			json.NewEncoder(w).Encode(f.share)

		case r.Method == http.MethodGet && r.URL.Path == "/v1/rules":
			json.NewEncoder(w).Encode(f.rules)

		case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/v1/photos/"):
			key := strings.TrimPrefix(r.URL.Path, "/v1/photos/")
			data, ok := f.photos[key]
			if !ok {
				w.WriteHeader(http.StatusNotFound)
				return
			}
			w.Write(data)

		case r.Method == http.MethodPost && strings.HasSuffix(r.URL.Path, "/drafts"):
			var body map[string]interface{}
			json.NewDecoder(r.Body).Decode(&body)
			f.postedBody = body
			f.postedCount++
			w.Write([]byte(`{}`))

		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
}

func fakeEnvelope(t *testing.T, modelJSONText string) string {
	t.Helper()
	envelope := map[string]string{"result": "here you go:\n" + modelJSONText}
	b, err := json.Marshal(envelope)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func baseTestConfig(inboxURL string) *Config {
	return &Config{
		InboxURL:  inboxURL,
		TokenEnv:  "DRAFTER_TOKEN",
		Claude:    []string{"claude", "-p"},
		VoiceFile: "", // set per test via a temp file
		Subs: []Sub{
			{Name: "Ducati", For: "his own bike, rides, parts"},
		},
	}
}

func withVoiceFile(t *testing.T, cfg *Config, contents string) {
	t.Helper()
	dir := t.TempDir()
	path := dir + "/voice.md"
	if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg.VoiceFile = path
}

func TestProcessOneNothingToClaim(t *testing.T) {
	worker := newFakeWorker()
	server := worker.server()
	defer server.Close()

	cfg := baseTestConfig(server.URL)
	withVoiceFile(t, cfg, "plain, lowercase, dry")

	d := &Drafter{
		Config: cfg,
		Client: NewInboxClient(server.URL, "tok"),
		RunClaude: func(args []string) (string, error) {
			t.Fatal("claude should not run when there is nothing to claim")
			return "", nil
		},
	}

	did, err := d.ProcessOne(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if did {
		t.Error("expected did=false when the inbox is empty")
	}
}

func TestProcessOneSuccessDropsUnconfiguredSubAndKeepsGoodDraft(t *testing.T) {
	worker := newFakeWorker()
	worker.share = &Share{ID: "share1", Note: "took the scrambler out this morning", Status: "drafting", Photos: []string{"share1/0.jpg"}}
	worker.photos["share1/0.jpg"] = []byte{0xff, 0xd8, 0xff, 0x01}
	worker.rules["Ducati"] = []string{"be nice"}
	server := worker.server()
	defer server.Close()

	cfg := baseTestConfig(server.URL)
	withVoiceFile(t, cfg, "plain, lowercase, dry")

	modelJSON := `{"drafts": [` +
		`{"sub": "Ducati", "title": "took the scrambler out this morning", "body": "", "why": "his bike", "rule_notes": "", "facts_from_note": ["rode this morning"], "facts_from_photo": []},` +
		`{"sub": "not_configured", "title": "x", "facts_from_note": [], "facts_from_photo": []}` +
		`]}`

	d := &Drafter{
		Config: cfg,
		Client: NewInboxClient(server.URL, "tok"),
		RunClaude: func(args []string) (string, error) {
			return fakeEnvelope(t, modelJSON), nil
		},
	}

	did, err := d.ProcessOne(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if !did {
		t.Fatal("expected did=true")
	}

	worker.mu.Lock()
	defer worker.mu.Unlock()
	if worker.postedCount != 1 {
		t.Fatalf("expected exactly one post to the drafts route, got %d", worker.postedCount)
	}
	draftsRaw, ok := worker.postedBody["drafts"]
	if !ok {
		t.Fatalf("expected a drafts key, got %+v", worker.postedBody)
	}
	drafts, ok := draftsRaw.([]interface{})
	if !ok || len(drafts) != 1 {
		t.Fatalf("expected exactly one kept draft, got %+v", draftsRaw)
	}
	kept := drafts[0].(map[string]interface{})
	if kept["sub"] != "Ducati" {
		t.Errorf("kept draft sub = %v, want Ducati", kept["sub"])
	}
	if kept["rules_checked"] != true {
		t.Error("rules_checked should be true since Ducati has cached rules")
	}
}

func TestProcessOneAllDraftsRejectedPostsFailure(t *testing.T) {
	worker := newFakeWorker()
	worker.share = &Share{ID: "share2", Status: "drafting", Photos: []string{}}
	server := worker.server()
	defer server.Close()

	cfg := baseTestConfig(server.URL)
	withVoiceFile(t, cfg, "plain")

	// Em dash makes the only draft fail its gate.
	badTitle := "morning ride " + string(rune(0x2014)) + " scrambler"
	modelJSON := `{"drafts": [{"sub": "Ducati", "title": "` + badTitle + `", "facts_from_note": [], "facts_from_photo": []}]}`

	d := &Drafter{
		Config: cfg,
		Client: NewInboxClient(server.URL, "tok"),
		RunClaude: func(args []string) (string, error) {
			return fakeEnvelope(t, modelJSON), nil
		},
	}

	did, err := d.ProcessOne(context.Background())
	if !did {
		t.Fatal("expected did=true")
	}
	if err == nil {
		t.Fatal("expected an error since every draft was rejected")
	}

	worker.mu.Lock()
	defer worker.mu.Unlock()
	if worker.postedBody["error"] == nil {
		t.Fatalf("expected the share to be reported failed, got %+v", worker.postedBody)
	}
}

func TestProcessOneClaudeErrorPostsFailure(t *testing.T) {
	worker := newFakeWorker()
	worker.share = &Share{ID: "share3", Status: "drafting", Photos: []string{}}
	server := worker.server()
	defer server.Close()

	cfg := baseTestConfig(server.URL)
	withVoiceFile(t, cfg, "plain")

	d := &Drafter{
		Config: cfg,
		Client: NewInboxClient(server.URL, "tok"),
		RunClaude: func(args []string) (string, error) {
			return "", errFakeClaude
		},
	}

	did, err := d.ProcessOne(context.Background())
	if !did || err == nil {
		t.Fatalf("expected did=true and a non-nil error, got did=%v err=%v", did, err)
	}

	worker.mu.Lock()
	defer worker.mu.Unlock()
	if worker.postedBody["error"] == nil {
		t.Fatalf("expected the share to be reported failed, got %+v", worker.postedBody)
	}
}
