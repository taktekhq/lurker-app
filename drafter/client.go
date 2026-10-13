package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Share mirrors the Share shape from SPEC.md. Drafts is left raw since the
// drafter only ever writes drafts, it never needs to parse ones that came
// back from the worker.
type Share struct {
	ID      string          `json:"id"`
	Note    string          `json:"note"`
	Status  string          `json:"status"`
	Created int64           `json:"created"`
	Updated int64           `json:"updated"`
	Photos  []string        `json:"photos"`
	Drafts  json.RawMessage `json:"drafts"`
	Error   *string         `json:"error"`
}

// InboxClient talks to the worker over HTTP with the drafter token.
type InboxClient struct {
	BaseURL string
	Token   string
	HTTP    *http.Client
}

func NewInboxClient(baseURL, token string) *InboxClient {
	return &InboxClient{
		BaseURL: baseURL,
		Token:   token,
		HTTP:    &http.Client{Timeout: 60 * time.Second},
	}
}

func (c *InboxClient) do(method, path string, body io.Reader) (*http.Response, error) {
	req, err := http.NewRequest(method, c.BaseURL+path, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.Token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	return c.HTTP.Do(req)
}

func readBody(resp *http.Response) string {
	b, _ := io.ReadAll(resp.Body)
	return string(b)
}

// Claim asks the worker for the next share to draft. A nil Share with a nil
// error means there is nothing to do right now.
func (c *InboxClient) Claim() (*Share, error) {
	resp, err := c.do("POST", "/v1/claim", nil)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNoContent {
		return nil, nil
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("claim: unexpected status %d: %s", resp.StatusCode, readBody(resp))
	}
	var share Share
	if err := json.NewDecoder(resp.Body).Decode(&share); err != nil {
		return nil, fmt.Errorf("claim: decode response: %w", err)
	}
	return &share, nil
}

// GetRules fetches the cached per-subreddit rules.
func (c *InboxClient) GetRules() (map[string][]string, error) {
	resp, err := c.do("GET", "/v1/rules", nil)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("get rules: unexpected status %d: %s", resp.StatusCode, readBody(resp))
	}
	rules := map[string][]string{}
	if err := json.NewDecoder(resp.Body).Decode(&rules); err != nil {
		return nil, fmt.Errorf("get rules: decode response: %w", err)
	}
	return rules, nil
}

// PutRules upserts the given subreddit -> rules map.
func (c *InboxClient) PutRules(rules map[string][]string) error {
	payload, err := json.Marshal(rules)
	if err != nil {
		return err
	}
	resp, err := c.do("PUT", "/v1/rules", bytes.NewReader(payload))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("put rules: unexpected status %d: %s", resp.StatusCode, readBody(resp))
	}
	return nil
}

// GetPhoto downloads one photo's bytes by its R2 key.
func (c *InboxClient) GetPhoto(key string) ([]byte, error) {
	resp, err := c.do("GET", "/v1/photos/"+key, nil)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("get photo %s: unexpected status %d: %s", key, resp.StatusCode, readBody(resp))
	}
	return io.ReadAll(resp.Body)
}

// PostDrafts marks a share drafted with the given drafts.
func (c *InboxClient) PostDrafts(id string, drafts []Draft) error {
	payload, err := json.Marshal(map[string]interface{}{"drafts": drafts})
	if err != nil {
		return err
	}
	return c.postShareUpdate(id, payload)
}

// PostFailed marks a share failed with the given reason.
func (c *InboxClient) PostFailed(id string, reason string) error {
	payload, err := json.Marshal(map[string]string{"error": reason})
	if err != nil {
		return err
	}
	return c.postShareUpdate(id, payload)
}

func (c *InboxClient) postShareUpdate(id string, payload []byte) error {
	resp, err := c.do("POST", "/v1/shares/"+id+"/drafts", bytes.NewReader(payload))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("post drafts/error for %s: unexpected status %d: %s", id, resp.StatusCode, readBody(resp))
	}
	return nil
}
