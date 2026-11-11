// DCGaming: the helper accepts only bundled presets, never remote/custom Lua.
// SPDX-License-Identifier: GPL-3.0-only
package strategies

type Strategy struct {
	ID   string
	Name map[string]string
	TCP  []string
	QUIC []string
}
type List struct{ Zapret2 []Strategy }
