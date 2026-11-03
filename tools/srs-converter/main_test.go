package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/sagernet/sing-box/common/srs"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
)

func TestConvertSRS(t *testing.T) {
	var input option.PlainRuleSet
	if err := json.Unmarshal([]byte(`{"rules":[{"domain_suffix":["example.com"]},{"ip_cidr":["192.0.2.0/24"]}]}`), &input); err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	source, output := filepath.Join(dir, "rules.srs"), filepath.Join(dir, "rules.json")
	file, err := os.Create(source)
	if err != nil {
		t.Fatal(err)
	}
	if err := srs.Write(file, input, C.RuleSetVersion1); err != nil {
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{source, output}); err != nil {
		t.Fatal(err)
	}
	content, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(content), "example.com") || !strings.Contains(string(content), "192.0.2.0/24") {
		t.Fatalf("domains and CIDRs not preserved: %s", content)
	}
	var parsed struct {
		Rules []map[string]any `json:"rules"`
	}
	if err := json.Unmarshal(content, &parsed); err != nil {
		t.Fatal(err)
	}
	if _, ok := parsed.Rules[0]["domain_suffix"].([]any); !ok {
		t.Fatalf("domain_suffix must be an array: %s", content)
	}
}

func TestRejectsCorruptSRS(t *testing.T) {
	dir := t.TempDir()
	source, output := filepath.Join(dir, "bad.srs"), filepath.Join(dir, "rules.json")
	if err := os.WriteFile(source, []byte("invalid"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{source, output}); err == nil {
		t.Fatal("corrupt file was accepted")
	}
	if _, err := os.Stat(output); !os.IsNotExist(err) {
		t.Fatal("output created for corrupt input")
	}
}

func TestRejectsUnsupportedConditions(t *testing.T) {
	for _, raw := range []string{
		`{"version":1,"rules":[{"domain_suffix":["example.com"],"port":[443]}]}`,
		`{"version":1,"rules":[{"domain_suffix":["example.com"],"ip_cidr":["192.0.2.0/24"]}]}`,
		`{"version":1,"rules":[{"domain_suffix":["example.com"],"invert":true}]}`,
	} {
		var rules option.PlainRuleSetCompat
		if err := json.Unmarshal([]byte(raw), &rules); err != nil {
			t.Fatal(err)
		}
		if _, err := normalizeRules(rules); err == nil {
			t.Fatalf("unsafe rule was accepted: %s", raw)
		}
	}
}
