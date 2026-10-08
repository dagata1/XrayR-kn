package mydispatcher_test

import (
	"encoding/json"
	"testing"

	"github.com/xtls/xray-core/app/dispatcher"
	"github.com/xtls/xray-core/app/proxyman"
	"github.com/xtls/xray-core/app/stats"
	"github.com/xtls/xray-core/common/serial"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf"

	"github.com/XrayR-project/XrayR/app/mydispatcher"
	_ "github.com/XrayR-project/XrayR/cmd/distro/all"
)

func inbound(t *testing.T, raw string) *core.InboundHandlerConfig {
	t.Helper()
	var c conf.InboundDetourConfig
	if err := json.Unmarshal([]byte(raw), &c); err != nil {
		t.Fatal(err)
	}
	h, err := c.Build()
	if err != nil {
		t.Fatal(err)
	}
	return h
}

func newInstance(t *testing.T, apps ...*serial.TypedMessage) *core.Instance {
	t.Helper()
	cfg := &core.Config{
		App: append(apps,
			serial.ToTypedMessage(&stats.Config{}),
			serial.ToTypedMessage(&proxyman.InboundConfig{}),
			serial.ToTypedMessage(&proxyman.OutboundConfig{}),
		),
		Inbound: []*core.InboundHandlerConfig{
			// VLESS inbound type-asserts the routing.DispatcherType() feature to
			// xray's *dispatcher.DefaultDispatcher: it must not panic.
			inbound(t, `{"tag":"vless","listen":"127.0.0.1","port":0,"protocol":"vless","settings":{"clients":[],"decryption":"none"}}`),
			inbound(t, `{"tag":"vmess","listen":"127.0.0.1","port":0,"protocol":"vmess","settings":{"clients":[]}}`),
		},
	}
	server, err := core.New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	return server
}

// Panel order: mydispatcher first, xray's dispatcher second.
func TestMyDispatcherHandlesInboundTraffic(t *testing.T) {
	server := newInstance(t,
		serial.ToTypedMessage(&mydispatcher.Config{}),
		serial.ToTypedMessage(&dispatcher.Config{}),
	)
	if err := mydispatcher.EnsureActive(server); err != nil {
		t.Fatal(err)
	}
	if _, ok := server.GetFeature(mydispatcher.Type()).(*mydispatcher.DefaultDispatcher); !ok {
		t.Fatal("mydispatcher feature not registered")
	}
}

// The 0.9.5/0.9.6 order put xray's dispatcher first, so inbounds bypassed
// mydispatcher (no block rules, no limiter). EnsureActive must catch that.
func TestEnsureActiveDetectsBypass(t *testing.T) {
	server := newInstance(t,
		serial.ToTypedMessage(&dispatcher.Config{}),
		serial.ToTypedMessage(&mydispatcher.Config{}),
	)
	if err := mydispatcher.EnsureActive(server); err == nil {
		t.Fatal("expected EnsureActive to report that xray's dispatcher is in use")
	}
}
