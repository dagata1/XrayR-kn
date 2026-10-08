// Package mydispatcher Package dispatcher implement the rate limiter and the online device counter
package mydispatcher

//go:generate go run github.com/xtls/xray-core/common/errors/errorgen

import (
	"fmt"

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/routing"
)

// Type returns the feature type token for the custom dispatcher feature.
// It intentionally differs from routing.DispatcherType(): xray-core's VLESS
// inbound type-asserts the routing.DispatcherType() feature to
// *dispatcher.DefaultDispatcher, so xray's dispatcher keeps that slot.
// Consumers should use server.GetFeature(mydispatcher.Type()) to access it.
func Type() interface{} {
	return (*DefaultDispatcher)(nil)
}

// EnsureActive checks that the routing.Dispatcher handed to inbounds and other
// features (core.RequireFeatures) is XrayR's dispatcher and not xray-core's.
// If it is not, panel block rules, speed limits and device limits are silently
// bypassed, so callers should treat an error as fatal.
func EnsureActive(server *core.Instance) error {
	var got routing.Dispatcher
	if err := server.RequireFeatures(func(d routing.Dispatcher) {
		got = d
	}, false); err != nil {
		return err
	}
	if got == nil {
		return fmt.Errorf("no routing.Dispatcher registered")
	}
	if _, ok := got.(*DefaultDispatcher); !ok {
		return fmt.Errorf("inbound traffic is dispatched by %T instead of XrayR's mydispatcher; "+
			"mydispatcher.Config must be listed before xray's dispatcher.Config", got)
	}
	return nil
}
