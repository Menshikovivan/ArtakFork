// SPDX-License-Identifier: GPL-3.0-or-later
// artak-srs converts sing-box SRS rule sets for the Xray routing plane.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"

	"github.com/sagernet/sing-box/common/srs"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
)

func hasAdGuardRules(rules []option.HeadlessRule) bool {
	for _, rule := range rules {
		switch rule.Type {
		case C.RuleTypeDefault:
			if len(rule.DefaultOptions.AdGuardDomain) != 0 {
				return true
			}
		case C.RuleTypeLogical:
			if hasAdGuardRules(rule.LogicalOptions.Rules) {
				return true
			}
		}
	}
	return false
}

// Xray's current importer supports positive domain OR IP matches. Do not
// silently flatten logical, inverted, port, source or combined AND rules.
func normalizeRules(rules option.PlainRuleSetCompat) (map[string]any, error) {
	encoded, err := json.Marshal(rules)
	if err != nil {
		return nil, err
	}
	var doc map[string]any
	if err := json.Unmarshal(encoded, &doc); err != nil {
		return nil, err
	}
	items, ok := doc["rules"].([]any)
	if !ok || len(items) == 0 {
		return nil, errors.New("rule set contains no supported rules")
	}
	for _, item := range items {
		rule, ok := item.(map[string]any)
		if !ok {
			return nil, errors.New("invalid rule")
		}
		domain, ip := false, false
		for key, value := range rule {
			switch key {
			case "domain", "domain_suffix", "domain_keyword", "domain_regex", "ip_cidr":
				if key == "ip_cidr" {
					ip = true
				} else {
					domain = true
				}
				if single, ok := value.(string); ok {
					rule[key] = []string{single}
				} else if _, ok := value.([]any); !ok {
					return nil, errors.New("invalid match list")
				}
			default:
				return nil, fmt.Errorf("unsupported rule condition: %s", key)
			}
		}
		if (!domain && !ip) || (domain && ip) {
			return nil, errors.New("unsupported empty or combined domain/IP rule")
		}
	}
	return doc, nil
}

func run(args []string) error {
	if len(args) != 2 {
		return errors.New("usage: artak-srs <input.srs> <output.json>")
	}
	in, err := os.Open(args[0])
	if err != nil {
		return err
	}
	defer in.Close()
	rules, err := srs.Read(in, true)
	if err != nil {
		return err
	}
	if hasAdGuardRules(rules.Options.Rules) {
		return errors.New("binary AdGuard rules cannot be decompiled")
	}
	doc, err := normalizeRules(rules)
	if err != nil {
		return err
	}
	out, err := os.Create(args[1])
	if err != nil {
		return err
	}
	if err = json.NewEncoder(out).Encode(doc); err != nil {
		out.Close()
		os.Remove(args[1])
		return err
	}
	return out.Close()
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
