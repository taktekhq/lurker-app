package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func checkAuth(t *testing.T, r *http.Request, want string) {
	t.Helper()
	if got := r.Header.Get("Authorization"); got != "Bearer "+want {
		t.Errorf("Authorization header = %q, want Bearer %s", got, want)
	}
}

func TestClaimReturnsNilOn204(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		checkAuth(t, r, "tok")
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()

	client := NewInboxClient(server.URL, "tok")
	share, err := client.Claim()
	if err != nil {
		t.Fatal(err)
	}
	if share != nil {
		t.Errorf("expected nil share, got %+v", share)
	}
}

func TestClaimReturnsShare(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(Share{ID: "abc", Status: "drafting", Photos: []string{"abc/0.jpg"}})
	}))
	defer server.Close()

	client := NewInboxClient(server.URL, "tok")
	share, err := client.Claim()
	if err != nil {
		t.Fatal(err)
	}
	if share == nil || share.ID != "abc" {
		t.Errorf("got %+v", share)
	}
}

func TestClaimErrorsOnUnexpectedStatus(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	client := NewInboxClient(server.URL, "tok")
	if _, err := client.Claim(); err == nil {
		t.Fatal("expected an error on a 500")
	}
}

func TestGetRules(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string][]string{"Ducati": {"be nice"}})
	}))
	defer server.Close()

	client := NewInboxClient(server.URL, "tok")
	rules, err := client.GetRules()
	if err != nil {
		t.Fatal(err)
	}
	if len(rules["Ducati"]) != 1 {
		t.Errorf("got %+v", rules)
	}
}

func TestGetPhoto(t *testing.T) {
	want := []byte{0xff, 0xd8, 0xff, 0x01}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/photos/abc/0.jpg" {
			t.Errorf("unexpected path %s", r.URL.Path)
		}
		w.Write(want)
	}))
	defer server.Close()

	client := NewInboxClient(server.URL, "tok")
	got, err := client.GetPhoto("abc/0.jpg")
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != string(want) {
		t.Errorf("got %v want %v", got, want)
	}
}

func TestPostDraftsSendsDraftsBody(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]interface{}
		json.NewDecoder(r.Body).Decode(&body)
		if _, ok := body["drafts"]; !ok {
			t.Error("expected a drafts key in the body")
		}
		w.Write([]byte(`{}`))
	}))
	defer server.Close()

	client := NewInboxClient(server.URL, "tok")
	if err := client.PostDrafts("abc", []Draft{{Sub: "Ducati", Title: "x"}}); err != nil {
		t.Fatal(err)
	}
}

func TestPostFailedSendsErrorBody(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]string
		json.NewDecoder(r.Body).Decode(&body)
		if body["error"] != "boom" {
			t.Errorf("got %+v", body)
		}
		w.Write([]byte(`{}`))
	}))
	defer server.Close()

	client := NewInboxClient(server.URL, "tok")
	if err := client.PostFailed("abc", "boom"); err != nil {
		t.Fatal(err)
	}
}

func TestPutRules(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPut {
			t.Errorf("method = %s", r.Method)
		}
		w.Write([]byte(`{"ok":true}`))
	}))
	defer server.Close()

	client := NewInboxClient(server.URL, "tok")
	if err := client.PutRules(map[string][]string{"Ducati": {"be nice"}}); err != nil {
		t.Fatal(err)
	}
}
