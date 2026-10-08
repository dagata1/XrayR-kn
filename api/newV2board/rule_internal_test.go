package newV2board

import "testing"

func TestCompileRouteMatch(t *testing.T) {
	p, err := compileRouteMatch([]string{`[:.]baidu\.com:`, "", "  ", `:1\.2\.3\.4:`})
	if err != nil {
		t.Fatal(err)
	}
	for dest, want := range map[string]bool{
		"tcp:www.baidu.com:80":        true,
		"tcp:baidu.com:443":           true,
		"tcp:1.2.3.4:80":              true,
		"tcp:notbaidu.com.example:80": false,
		"tcp:example.com:80":          false, // empty entries must not match everything
	} {
		if got := p.MatchString(dest); got != want {
			t.Errorf("%s: got %v want %v", dest, got, want)
		}
	}
	if _, err := compileRouteMatch([]string{"a("}); err == nil {
		t.Error("invalid regexp should be an error, not a panic")
	}
	if _, err := compileRouteMatch([]string{"", " "}); err == nil {
		t.Error("route with only empty matches should be skipped")
	}
}

func TestGetNodeRuleSkipsInvalid(t *testing.T) {
	c := &APIClient{}
	c.resp.Store(&serverConfig{Routes: []route{
		{Id: 1, Match: []string{"a("}, Action: "block"},
		{Id: 2, Match: []string{`[:.]baidu\.com:`}, Action: "block"},
		{Id: 3, Match: []string{"google.com"}, Action: "dns", ActionValue: "8.8.8.8"},
	}})
	rules, err := c.GetNodeRule()
	if err != nil {
		t.Fatal(err)
	}
	if len(*rules) != 1 || !(*rules)[0].Pattern.MatchString("tcp:www.baidu.com:80") {
		t.Fatalf("unexpected rules: %+v", *rules)
	}
	// No routes at all -> empty list (so the controller clears old rules).
	c.resp.Store(&serverConfig{})
	if rules, _ := c.GetNodeRule(); len(*rules) != 0 {
		t.Fatalf("expected no rules, got %d", len(*rules))
	}
}
