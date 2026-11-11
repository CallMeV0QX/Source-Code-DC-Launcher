# NestG BetterSteamTools runtime

Upstream: https://github.com/madoiscool/BetterSteamTools

Source commit: `4747385bdc7c92fb422e63419a5093566b3bf626` (v1.0.4).
NestG native version: `1.0.4-nestg.9`. Bundle ID: `bettersteamtools-cloud`, current candidate version `1.0.11`.
The runtime DLL is `OpenSteamTool.dll`; both `dwmapi.dll` and `xinput1_4.dll` load this name.
The configuration filename remains `opensteamtool.toml`.

The standalone update transition is documented in
[runtime-auto-update.md](../../docs/runtime-auto-update.md). Bridge `1.0.12` adds
`runtime-update.patch` after the existing five patches. Its proxy worker pins and
starts the separate helper before deciding whether a protected local compatibility
gate allows loading `OpenSteamTool.dll`. Routine runtime releases use separately
signed, authenticated channels; the upstream native self-updater stays disabled.
V1 stages updates while Steam runs and applies them after a natural Steam exit.
It does not automatically close/restart Steam without a proven save-idle signal.
`Build-Runtime.ps1` now requires the published helper's `-RuntimeUpdaterSha256`.
`Build-UpdateBootstrap.ps1`, `Test-UpdateBootstrap.ps1` and
`Package-UpdateBootstrap.ps1` build, isolate-test and package the bridge proxies.

Bundle `1.0.11` adds reviewed metadata for Steam `11.15.70.27`, build `1792618285`:
steamclient SHA-256 `253e0a11a4415b38c78a42f7bdd6ecc426455f06c1ba6453a48090df3142dbbc`
and SteamUI SHA-256 `cd9226db4e6c28942df70c22c0475d91fdd62cba5f100baae2d65af57cabb610`.
It preserves all 17 payloads from `1.0.10`, including native DLLs and the complete
corresponding-source archive, and adds three TOMLs for 20 full / 19 core files.
The new steamclient pattern also carries the deterministic `FindOrCreateKey` and
`ReadAsBinary` aliases required by the unchanged native lookup names. Historical
bundles/pins and `latest.json` (`1.0.1`) remain unchanged. Deploy and verify the
authenticated exact-version full/core routes before distributing the companion
desktop `2.2.45` / build `25`. A public desktop must use the production API endpoint;
the repository's local-test `https://localhost/` configuration must not be shipped
to customers. `Package-SteamMetadata111.ps1` pins raw upstream hashes, derives the
two aliases, verifies predecessor bytes and refuses an existing release directory.
See [1.0.11 validation and release checks](../../docs/steam-metadata-111-validation.md)
for provenance, commands, release gates and outstanding Steam/save validation.

Historical bundle `1.0.7` added metadata for Steam module file version `11.12.30.07`:
steamclient SHA-256 `e9045710ec7ee47d7b7488d1c5dda2d933dec7e251e965967a5c48f4df68eb4e`
and SteamUI SHA-256 `1b9457943205dc3af0bd53463ba331cbd2a381388699705c02271aac7a2b1252`.
It retains all fourteen payloads from `1.0.6`, including all four DLLs and the
corresponding-source archive. The new steamclient pattern TOML adds two reviewed
native lookup aliases, `FindOrCreateKey` and `ReadAsBinary`, using the matching
upstream KeyValues entries for this exact Steam build. Final file pins cover the
derived TOML bytes; upstream commit and SHA-256 checks precede the transformation.
That release has 17 full-bundle files and 16 core files. Historical releases and
`latest.json` (`1.0.1`) remain immutable. Its companion desktop was `2.2.44` / build `24`.
Static metadata checks do not establish native activation or a save round-trip;
those require disposable Steam/save data.

`nestg.patch` contains the original private-build changes:

- Self-updater excluded; CMake rejects enabling it.
- Manifest donation disabled at the native configuration boundary.
- `bst://` registration/redemption source files excluded.
- Steam pattern/IPC metadata loaded only from the matching local SHA-256 cache; remote fetch is disabled.
- Dependencies pinned to commits; Lua archive verified against the checksum published at https://www.lua.org/ftp/ and TLS verification enabled.
- CMake output and both proxy loader targets renamed to `NestG.dll`.

`Build-Runtime.ps1` clones the exact revision, applies `nestg.patch`, `startup.patch`, `opensteamtool.patch`, `shutdown.patch`, then `rental.patch`, and builds Release x64 with matching PDBs for diagnostics.
It requires MSVC x64 build tools, Windows SDK, CMake and Ninja in the calling environment.
The checked-in binary was built with MSVC 19.44.35229, Windows SDK 10.0.26100,
CMake 3.31.8 and Ninja 1.13.2, using the static MSVC runtime.
PE timestamps/tool versions can change output hashes: rebuilds require reviewed new server and embedded client pins.

CloudRedirect 2.6.5 and the original three Steam metadata files are reused byte-for-byte from the legacy bundle.
The metadata files were also checked against `madoiscool/steam-monitor`:
pattern commit `977aac5dbdb6e0a47e1f1ede0b5633217232e56f`;
IPC commit `7deb2817e89be646d1230ea47367825b4d3a1061`.
Only the Steam module hashes named in these metadata filenames are supported by this bundle.

Version `1.0.1` adds three upstream metadata files for `steamclient64.dll` SHA-256
`caba4826aa3501039d095aee1843a6bfb270fb43a3ab4455b2d6733223579fee` and `steamui.dll`
SHA-256 `cb387adefbbac64a3c1490d4275d00daf3a1e0219b4580726ef7681db7429278` (local file
version `10.96.30.42`). The same upstream commits above contain these files.
`Update-SteamMetadata.ps1` reproduces the new release from `1.0.0`, checks explicit
SHA-256 pins on the downloads, and updates the server latest pointer and embedded client
manifest. Native binaries and the corresponding source archive remain identical.
Both version directories are retained; distribute the rebuilt desktop with the new server bundle.

`Test-SteamMetadata.ps1 -SteamDirectory <Steam> -MetadataDirectory <bundle>` only reads files:
it checks exact module hashes, PE x64 layout, pattern bytes at executable RVAs and IPC
vtable entries. The 1.0.11 inputs require 36 upstream patterns, two derived alias
patterns and six IPC vtable entries to match the exact new module bytes.
It does not load a DLL, start/stop Steam, touch saves or prove native activation success.

`Package-Runtime.ps1` creates the initial `1.0.0` authenticated server bundle and matching embedded client manifest.
It never modifies the legacy bundle. Supply a complete corresponding source archive, including patched
upstream source and dependency source, for distribution with the GPL runtime.
The package also includes licenses, this recipe and the native patch.
See `docs/bettersteamtools-validation.md` for release validation.

`Package-RenamedRuntime.ps1` creates immutable `1.0.3` from `1.0.2`, replacing the three
native DLLs, notices and complete corresponding source archive, then updating the current client pin.
It validates PE x64 and both loader target strings. All six Steam metadata files and CloudRedirect
remain unchanged. Keep the old release directories and historical desktop pins.
`latest.json` intentionally stays at `1.0.1` for released desktops; new desktops request
authenticated metadata at `/api/runtime-bundles/bettersteamtools-cloud/1.0.3`.
Deploy the server endpoint and bundle before distributing the new desktop.

Version `1.0.4` fixes the DWM proxy's self-referencing forwarders with x64 argument-preserving
tail-call thunks into the actual System32 module. The original 103 export names/ordinals remain.
Both proxies schedule runtime loading outside DllMain, use an absolute Unicode path next to
the proxy, and call `NestGInitialize`. NestG initialization runs once across both loaders.
Missing/invalid NestG.dll does not fail the OS proxy's DllMain. XInput resolves its system
functions once under concurrent calls. Native modules are pinned for process lifetime;
DllMain does not join watchers or call CloudRedirect shutdown during process termination.
Release writes only bounded stage/error/PID diagnostics to `opensteamtool/nestg_startup.log`;
upstream verbose logs remain disabled. This log is evidence, not activation success.

`Test-NativeLoaders.ps1` compiles disposable hosts (including a fixture named steam.exe),
tests exports, concurrent DWM calls, XInput, missing/invalid runtime, Unicode paths and
both proxies initializing once. It never launches the installed Steam or reads saves.
MSVC x64, Windows SDK and MASM (`ml64`) are required. `Collect-ActivationDiagnostics.ps1`
collects bounded logs, module fingerprints and selected Steam crash event fields without
launching Steam or copying account/provider/save files.

`Package-StartupRuntime.ps1` creates immutable `1.0.4` from `1.0.3`, retaining a historical
1.0.3 desktop pin. Old bundles and `/latest` (1.0.1) are unchanged. The new desktop requests
`/api/runtime-bundles/bettersteamtools-cloud/1.0.4`. Ship the server artifact first.
CloudRedirect 2.6.5 and all six Steam metadata files remain byte-for-byte identical.
These fixes are supported by isolated reproductions, not proof of the customer's unique
crash cause. Real Steam/game/save round-trip on a disposable installation is still required.

Version `1.0.2` used `NestGSteamTools.dll`; its immutable bundle and source archive
retain that release's patch and packaging recipe. The 1.0.4 migration handled both
old names (`OpenSteamTool.dll`, `NestGSteamTools.dll`) with pinned ownership checks,
transactional deletion and rollback. It does not rename user Lua/config folders.

Version `1.0.5` returns the main filename to `OpenSteamTool.dll`. `opensteamtool.patch`
changes the native output and absolute loader target together, retaining all 1.0.4
startup fixes and the `NestGInitialize` contract. `Package-OpenSteamToolRuntime.ps1`
creates the immutable release from 1.0.4, preserves its historical client pin and
updates the current pin. `/latest` remains 1.0.1; current desktop requests exact 1.0.5.

Current ACTIVE accepts an existing OpenSteamTool.dll as a replacement target after
confirmed graceful Steam closure. Downloaded bytes still require independent client
pins, size/SHA-256 and PE x64 validation. Publication uses flushed adjacent temporary
files, per-file atomic replacement and target-drift checks under the operation
coordinator. ACTIVE creates no transaction/recovery journal and performs no automatic
rollback; files already published by a failed full attempt remain for its one core
retry. Only pinned predecessor DLLs may be removed. Existing valid config/Lua/provider/
token/sync settings are preserved, and core mode disables the cloud host. Manual
CloudRedirect management retains its separate protected backup/recovery/rollback
transactions; those runtime/config backups do not cover saves. See
`docs/activation-simple-steam-validation.md` and `docs/steam-rollback-safety-validation.md`.

Version `1.0.6` fixes process-exit termination by the two global joinable watcher
threads. `shutdown.patch` retains each complete watcher state (thread, paths, flag,
mutex) for the lifetime of the already-pinned DLL. Windows reclaims it at process
termination; there is no CRT thread destructor, detach-time join or cloud shutdown.
Explicit Stop/Start during live configuration reload still joins the old worker
before replacing paths and serializes concurrent lifecycle calls.

`Test-NativeShutdown.ps1` compiles the actual archived watchers and Windows directory
notification backend in a disposable DLL/host, replacing only Steam/config effects.
`-ExpectHistoricalFailure` reproduces 1.0.5's `0xc0000409` on normal exit and an
early-returned worker. The fixed source additionally covers immediate process exit,
config reload followed by a Lua change, restart and concurrent Start/Stop. No installed
Steam, accounts or saves are used. This proves the watcher defect, not the exact
customer crash stack or real Steam/save compatibility.

`Package-ShutdownRuntime.ps1` creates immutable `1.0.6`, retains the `1.0.5` client
pin and updates the current pin. CloudRedirect and all six metadata files are copied
unchanged. `/latest` stays at 1.0.1. Deploy the authenticated 1.0.6 bundle before the
updated desktop. Keep the matching PDBs with release diagnostics, outside the runtime
download set. See `docs/activation-shutdown-106.md` for validation and rollout.

Version `1.0.8` adds `rental.patch` after the existing four patches. Native version
`1.0.4-nestg.7` observes authenticated Steam network identity, keeps rental Lua data
in a separate restricted parser, routes authorized manifest reads into private
per-account directories and withdraws only the rental contribution on identity or
authorization changes. It never publishes rental manifests into `depotcache`.
Server-confirmed expiration encrypts private payloads with CurrentUser DPAPI;
network failures only suspend the source after its current allowance expires.

`Test-RentalIdentity.ps1`, `Test-RentalRuntime.ps1` and `Test-RentalPackage.ps1`
exercise identity transitions, actual Windows file detours/DPAPI and simulated
Steam package callbacks. These fixtures do not prove Steam's live internal ABI,
library refresh, login switching or game/save compatibility. Unsupported identity,
manifest access or Lua commands fail closed. The server rental-runtime feature
defaults to disabled; localhost can opt in for manual testing. A local opt-in does
not establish disposable real-Steam validation.

`Package-RentalRuntime.ps1` originally created immutable `1.0.8` from `1.0.7`, retaining the
historical client pin and packaging the corresponding source and dependency source.
It preserves CloudRedirect, Steam metadata and the `/latest` pointer at `1.0.1`.
The script now defaults to creating `1.0.10` from `1.0.9`; explicit release and
predecessor arguments retain the original packaging recipe. Existing release
directories are immutable. The rebuilt desktop requests authenticated exact-version
`1.0.10` metadata for that historical native release. The metadata-only `1.0.11`
release retains its native payloads and adds a historical `1.0.10` client pin.

Version `1.0.9` adds a local, read-only login-status protocol to the rental runtime.
The endpoint belongs to the newly launched Steam PID and creation time. Its
bounded messages carry a fresh challenge and observed identity/authorization state,
never login credentials, JWTs or the opaque runtime proof. The desktop checks the
pipe server process and Windows context, and completion requires the original
authenticated Steam identity, exact rental/account/installation/grant/revision and
a current monotonic authorization allowance. A requested SteamID is never identity
evidence. Unsupported hooks, stale process/identity generations, ambiguous logon
attempts and unavailable authorization cannot produce successful confirmation.
`NestGRentalStatusProtocolVersion` reports status protocol 1; the rental capability
mask adds bit `0x20` to the existing isolation features.

The rental launcher separately verifies process readiness before shutdown, so a
missing or valid-empty `loginusers.vdf` does not prevent a safe account switch.
The admin prototype retains its strict local-identity verification. Windows process
arguments still have the existing `-login` limitation; the status protocol does not
claim protection from a machine administrator or code already controlling Steam.
Native fixtures and local HTTP checks do not certify real Steam login, Guard,
game visibility or save compatibility. Those require disposable Steam/account/save
end-to-end verification.

Version `1.0.10` fixes the rental file adapter's startup stack overflow. The
object-name query buffer is allocated on the heap only when a relative NT name
requires resolving its directory handle. Ordinary absolute file opens no longer
reserve 64 KiB in `ObjectName()`. Allocation failure returns access denied
through the adapter exception boundary and cannot bypass the rental checks.
Rental protocol 1, status protocol 1, isolation capabilities and private manifest
layout retain their existing contracts. CloudRedirect and Steam metadata are
copied unchanged from `1.0.9`; the new bundle retains 17 full / 16 core files.

Create a new source/build directory using `Build-Runtime.ps1`, or build an
equivalent fresh source tree containing the full pinned `.deps/*-src` dependency
sources. After source and regression fixtures are final, create and verify the
corresponding source ZIP before publishing the runtime:

```powershell
./tools/BetterSteamTools/Package-RentalSource.ps1 `
    -SourceDirectory <patched-source-with-dependencies> `
    -WorkDirectory .codex-temp/rental-runtime-native-110/source-package
./tools/BetterSteamTools/Package-RentalRuntime.ps1 `
    -NativeOutputDirectory <build>/Release `
    -CorrespondingSourceArchive .codex-temp/rental-runtime-native-110/source-package/BetterSteamTools-NestG-source-1.0.10.zip
./tools/BetterSteamTools/Test-RuntimeBundle.ps1
```

`Test-RentalStack.ps1 -SourceDirectory <candidate> -HistoricalSourceDirectory
<immutable-1.0.9-source> -WorkDirectory <new-.codex-temp-child>` builds the real
NT file hooks with `/O2 /MT` and checks measured 64/128/256 KiB thread and fiber
stack reserves. Cases cover ordinary and Unicode relative file access, private
path denial, authorized routing, revocation and allocation failure. Historical
cases establish the original stack overflow in separate disposable processes.

The source helper uses a new temporary directory, reconstructs clean upstream
source from the immutable `1.0.7` archive, reapplies all five patches and compares
all 157 native source files. It includes dependency source and the current build,
patch, package and fixture recipes; it excludes toolchains and binary output.
It leaves the supplied source tree and historical archives unchanged. Packaging
checks the native version and exact embedded build/patch recipes before publishing
the new immutable release and current desktop pin. It preserves the `1.0.9`
historical pin and `/latest` at `1.0.1`. Keep the release DLL/PDB pairs outside the
runtime download set. Native fixtures and artifact checks still require the
separate disposable Steam/account/save verification before a production claim.
