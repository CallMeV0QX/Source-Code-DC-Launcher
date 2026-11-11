# DC Gaming Steam DPI helper

Ported from NestG's `app_desktop` Steam DNS/DPI integration. DC Gaming uses
its own `DCGamingSteamDpi-*` pipes, helper mutex, ProgramData runtime directory,
`DCGamingSteamDns:` policy tags and `DCGamingSteamDnsRecovery.v2` recovery task.
It never owns or cleans NestG's policies/runtime. The TCP profiles, provider
validation, protected journal and recovery protocol are preserved.

Standalone GPL-3.0-only derivative of Ghostline commit
`b1ca3f3208f9a41cd888d69b8ff8bcfa8e22c28c` (2026-10-07).
Copyright Ghostline contributors / Harry Nguyen; NestG modifications 2026.

This module reuses Ghostline's DPI manager, zapret2 argument builder/validator,
hash pins, embedded runtime and Windows process utilities. The inherited DNS layer
uses standard Go wire-format DoH and a bounded loopback UDP/TCP relay. It has no
Wails, adapter DNS changes, system proxy, certificate installation or LAN listener.
Fixed Steam namespaces receive an owned NRPT rule. A protected journal,
independent guardian and SYSTEM startup/logon recovery task restore orphan rules.
The recovery task/executable persist outside the install folder; with an empty
journal they do not change settings or access the network.

Changes from upstream:

- Three bundled TCP-only profiles (`z-split`, `z-disorder`, `z-fake`), a fixed
  Steam host list and no arbitrary Lua, command arguments or remote strategies.
- Private launcher-owned pipe; both peers check the other process's identity.
  Parent creation time and a retained parent handle reject reused PIDs.
- A machine-wide helper mutex, parent watchdog and pipe-disconnect cleanup.
- Suspended engine start; job assignment and thread resumption must succeed.
  Kill-on-close jobs own only that engine. Failure cannot leave it running.
- Never stop or delete shared WinDivert services. Foreign/inconclusive active
  drivers are refused. A driver at the protected, pinned DC Gaming path can be reused.
- Admin-owned `%ProgramData%/DCGamingSteamDpiRuntime/<commit>` runtime directories,
  checked reparse points, pinned native/Lua files and write-denying file leases.
- Cancellation checks, waiting for owned child exit, bounded line-based JSON.
- Protocol v2 accepts `dns-only` first, then the three fixed TCP profiles only
  if needed. It reports DNS readiness and DPI activity separately. The running
  flag retains incomplete DNS cleanup so the UI can retry Stop.
- The relay refuses foreign namespaces and validates DNS wire replies; 32
  workers, 256 simple-question cache entries and a 60-second TTL ceiling bound
  resources. Truncated UDP responses fall back to the TCP listener.
- Cloudflare/Google fixed DoH providers use normal TLS name/certificate checks.
  Redirects, private addresses, malformed replies and wrong DNS IDs are rejected.
- NRPT operations preserve overlapping/modified policies. A crash between Add
  and saving the returned GUID is recovered by the random journaled tag.
- PowerShell children join owned jobs before executing; module search is reset
  to system modules and inherited CLR profiler/startup hooks are excluded.

Build with Go 1.26.8 or newer, Windows x64. `vendor/` and `go.sum` permit an offline build:

```powershell
go test -mod=vendor ./...
go build -mod=vendor -trimpath -buildvcs=false -ldflags '-s -w -H=windowsgui' -o DCGaming.SteamDpi.Helper.exe .
```

From repository root, `node tools/Build-SteamDpiHelper.mjs <path-to-go.exe>`
tests and rebuilds the executable, manifest, complete corresponding-source ZIP
and license copies under `app_desktop/Assets/SteamConnection/Runtime`.
Rebuild the launcher after changing any helper source. Ordinary launcher builds
use this bundled executable and do not require Go or internet access.

`--self-test` only checks embedded file hashes; it does not request elevation,
extract files, open WinDivert or change Windows settings. Normal operation needs
the launcher-verified private IPC session and elevation. `--recover-dns` and
`--dns-guardian` use only the protected journal/verified process identity; there
is no arbitrary DNS, script, executable or rule configuration CLI.

Read-only network validation, without elevation or Windows policy changes:

```powershell
$env:DC_STEAM_DNS_NETWORK_TEST='1'
go test -mod=vendor -count=1 -run '^TestReadOnlyRealSteamHTTPSUsingEncryptedDNS$' -v ./internal/steamdns
```

This checks fixed Steam HTTPS requests using the production DoH resolver.
It does not establish NRPT application, crash/boot recovery or Steam client login.

Third-party binaries are unmodified zapret2 v1.0.5.2 (MIT), WinDivert 2.2
(LGPLv3) and the Cygwin runtime shipped in that release (LGPLv3). Full notices
are in `assets/`. Windows API dependency `golang.org/x/sys v0.47.0` is BSD;
its vendored license is included. Preserve licenses and corresponding source
with distribution. Native dependency source/build references:

- https://github.com/hashcott/ghostline/tree/b1ca3f3208f9a41cd888d69b8ff8bcfa8e22c28c
- https://github.com/bol-van/zapret2/tree/v1.0.5.2
- https://github.com/basil00/WinDivert/tree/v2.2.2
- https://cygwin.com/packages/summary/cygwin.html

The source ZIP covers this modified helper and its Go dependency. Before an
external release, verify corresponding-source distribution obligations for
the exact native dependency binaries as well; source links alone are not an
assertion that all LGPL obligations have been fulfilled.

Host scoping applies by domain, not by Steam PID. TCP 80/443 interception can
still affect timing of other traffic passing through WinDivert. HTTP probes
do not establish Steam account login, CM/UDP connectivity, game compatibility
or effectiveness on every ISP. Real disposable-Windows/Steam validation and
business-flow regression checks remain release requirements.
