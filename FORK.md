# Fork notes — Screenflare actions

This is a personal fork of [OpenLogi](https://github.com/AprilNEA/OpenLogi), based on
upstream `433e414` (v0.8.19). It adds one thing upstream does not have: a
**`Screenflare*` action group**, so [Screenflare](https://screenflare.app)
captures and recordings can be bound to a mouse button or placed in an Actions Ring
slot, next to the ten stock Screenflare entries instead of an anonymous
`RunShellCommand` row.

Nothing is proposed upstream yet. Treat this branch as "mine, kept building".

## What the action group does

`Screenflare` becomes an eleventh `Category`, and ten payload-free `Action`
variants join the catalogue. Each maps to one `screenflare-ctl` subcommand
(`crates/openlogi-core/src/binding/action.rs::screenflare_command`):

| Action | `screenflare-ctl` |
| --- | --- |
| `ScreenflareCaptureArea` | `action capture-area` |
| `ScreenflareCaptureWindow` | `action capture-window` |
| `ScreenflareCaptureFullscreen` | `action capture-fullscreen` |
| `ScreenflareCaptureScrolling` | `action capture-scrolling` |
| `ScreenflareCaptureText` | `action capture-text` |
| `ScreenflareRecordDisplay` | `action record-display` |
| `ScreenflareRecordWindow` | `action record-window` |
| `ScreenflareRecordArea` | `action record-area` |
| `ScreenflareToggleRecording` | `toggle` (stop if recording, else record a display) |
| `ScreenflareStopRecording` | `action stop-recording` |

`screenflare-ctl` is the companion CLI in `~/i/screenflare-ctl`: a Swift binary that
presses Screenflare's own menu items through the Accessibility API, because
Screenflare ships no URL scheme, AppleScript dictionary, CLI or App Intents.

Runtime path: `Action` → `Effect::Screenflare(&'static str)` → macOS injector
`run_screenflare`, which looks the tool up and runs it **detached**
(`--no-wait --json`, null stdio, reaping thread). Detaching matters: the injector
runs on the hook/gesture dispatch thread, and a capture lasts as long as the user
keeps the overlay open.

Linux and Windows compile a documented no-op: the whole path is macOS-only.

## Files touched

```
crates/openlogi-core/src/binding/action.rs      10 variants, macro rows, screenflare_command()
crates/openlogi-core/src/binding/category.rs    Category::Screenflare
crates/openlogi-core/src/binding/effect.rs      Effect::Screenflare, effect() arm
crates/openlogi-core/src/binding/tests.rs       persisted-name snapshot + catalogue test
crates/openlogi-agent-core/src/runtime/pointer.rs  focus group (needs a focused window)
crates/openlogi-inject/src/inject/macos.rs      run_screenflare, screenflare_ctl, spawn_screenflare
crates/openlogi-inject/src/inject/macos/tests.rs   spawn-contract test
crates/openlogi-inject/src/inject/{linux,windows}.rs  no-op stub
crates/openlogi-desktop/src/features/binding_editor.rs  per-action picker icon
crates/openlogi-ui/locales/*.toml               11 keys in all 24 catalogues
docs/CONFIGURATION.md, docs/config.example.toml  documentation + examples
```

Test suites (`cargo fmt --check`, `cargo clippy --all-targets` clean):

```
openlogi-core        434 + 625 passed
openlogi-inject       98 passed (1 ignored: pre-existing)
openlogi-agent-core  625 passed
openlogi-ui            6 + 1 catalogue-parity passed
```

## Build

`cargo run -p xtask -- macos bundle` is the supported path, but it shells out to
`actool` and `xcrun` under Xcode 26 (Icon Composer), so it cannot run on a Command
Line Tools-only Mac. This fork builds the way that machine can:

```sh
# 1. binaries. Two build-time settings matter — see below.
OPENLOGI_UPDATE_BASE_URL=https://updates.invalid \
  cargo build --release -p openlogi-desktop -p openlogi-overlay \
                     -p openlogi-agent -p openlogi

# 2. bundle: borrows the layout of an installed upstream OpenLogi.app (Info.plists,
#    icons, the LaunchAgent that starts the agent, the nested helper apps), swaps in
#    the four release binaries, ad-hoc signs it.
dist/bundle.sh                 # → dist/OpenLogi.app
dist/install.sh                # → /Applications/OpenLogi.app (backup in dist/, never beside it)
dist/install.sh --rollback    # or: brew reinstall --cask openlogi
```

The two settings, both deliberate:

* **`gpui_platform/runtime_shaders`** (enabled in the workspace `Cargo.toml`). GPUI's
  build script otherwise compiles `shaders.metal` with `xcrun metal`; with the feature
  it stitches the source into the binary and the Metal driver compiles it on first
  launch. Identical rendering, a few milliseconds slower first launch, no Xcode.
  Revert that `Cargo.toml` line to build the upstream way.
* **`OPENLOGI_UPDATE_BASE_URL=https://updates.invalid`**. The update host is compiled
  in; pointing it at a non-resolving domain means a check fails closed instead of
  fetching a signed upstream bundle that would erase this patch. With no Sparkle key
  and no minisign key the bundle carries the built-in engine, which refuses every
  manifest by design.

Consequence of the shortcut: the bundle is **ad-hoc signed**, and macOS keys
Accessibility / Input Monitoring grants to the signature, so both are asked for again
after installing. It also ships no Sparkle framework and no agent provisioning
profile (the agent falls back to `CGEventPost` rather than the virtual HID keyboard;
neither affects Screenflare actions).

Status: all four release binaries build, `dist/bundle.sh` produces a bundle that
passes `codesign --verify --deep --strict`, its embedded CLI runs (`openlogi 0.8.19`),
and the GUI binary carries the new locale strings. **Not yet verified:** the bundle
launched, the picker showing the Screenflare group, and a physical button press.

## Tool discovery

`run_screenflare` looks for `screenflare-ctl` in this order, so a launchd-started
agent (whose `PATH` is `/usr/bin:/bin:/usr/sbin:/sbin`) still finds a user install:

1. `$SCREENFLARE_CTL`
2. `~/bin`, `~/.local/bin`, `~/i/screenflare-ctl/bin`
3. `/opt/homebrew/bin`, `/usr/local/bin`
4. every `PATH` entry

Missing tool → one `tracing::warn` per press, no other effect.

## Update guard — read before installing this build

Upstream's update host is compiled into the bundle (`OPENLOGI_UPDATE_BASE_URL`,
defaulting to `https://updates.openlogi.org`), so a stock update would replace this
patch with a signed upstream OpenLogi. Point the build at an unusable host and give
it no Sparkle key, so a check fails closed and no upstream bundle is ever fetched:

```sh
OPENLOGI_UPDATE_BASE_URL=https://updates.invalid \
  cargo run -p xtask -- macos bundle
```

That also sidesteps the two release-only secrets upstream injects: the EdDSA
`SUPublicEDKey` (which would need Xcode's `generate_keys`) and
`OPENLOGI_UPDATE_MINISIGN_PUBLIC_KEY`. With neither set, the bundle carries the
built-in update engine with no signing key, which by design refuses every manifest.

Also turn **Settings ▸ Updates ▸ check automatically** off in this build, and keep
upstream's own app (or the Homebrew cask) out of `/Applications` while this bundle
is installed — they share `org.openlogi.openlogi` and `~/.config/openlogi/config.toml`.

`org.openlogi.agent` is a LoginItem of the bundle: replacing the bundle replaces the
agent, so **restart OpenLogi** after installing.

## Trying it

1. `make -C ~/i/screenflare-ctl install` (or leave `bin/screenflare-ctl` in place —
   discovery covers `~/i/screenflare-ctl/bin`).
2. `dist/bundle.sh && dist/install.sh` — quits OpenLogi, installs the fork, relaunches.
3. The agent cannot start through SMAppService — re-signing trips launchd's
   launch constraint (`OS_REASON_CODESIGNING | Launch Constraint Violation`,
   `last exit code = 78: EX_CONFIG` in `launchctl print`), and no Login Items
   toggle can fix that because the toggle records *approval*, not a *constraint*.
   Start it from a user LaunchAgent instead:

   ```sh
   dist/agent-launchagent.sh install     # ~/Library/LaunchAgents/app.openlogi.agent.fork.plist
   dist/agent-launchagent.sh uninstall
   ```

   Because launchd execs that job directly, macOS attributes privacy grants to
   **OpenLogi Agent**, not to OpenLogi: add
   `/Applications/OpenLogi.app/Contents/Library/LoginItems/OpenLogi Agent.app` to
   **System Settings ▸ Privacy & Security ▸ Accessibility** and **Input
   Monitoring** (`＋`, then ⌘⇧G to paste the path). Verify with
   `openlogi api status --json` — `accessibility_granted`, `input_monitoring_granted`
   and `hook_installed` must all be `true`.

   `dist/bundle.sh` signs each nested bundle with an identifier-only designated
   requirement (`designated => identifier "org.openlogi.agent"`), so those grants
   survive rebuilds; a cdhash-pinned requirement would invalidate them every time.

4. Button editor → action picker → **Screenflare**, or in `config.toml`:

```toml
[devices."unit:69ac62c8".bindings]
Back = "ScreenflareCaptureWindow"
Forward = "ScreenflareToggleRecording"

[devices."unit:69ac62c8".action_ring.default.slots]
Top = { action = "ScreenflareCaptureArea", label = "Capture Area" }
Bottom = { action = "ScreenflareToggleRecording", label = "Record / Stop" }
```

5. Press it. Expected: Screenflare's overlay appears, OpenLogi stays responsive, the
   finished file lands in `~/Screenflare/screenshots`.

   To exercise the dispatch chain without a mouse, the fork ships an example that
   calls the same `openlogi_inject::execute` a press does:

   ```sh
   cargo run -q -p openlogi-inject --example screenflare -- capture-fullscreen
   cargo run -q -p openlogi-inject --example screenflare -- toggle
   ```
6. `dist/install.sh --rollback    # or: brew reinstall --cask openlogi` restores the upstream bundle from `OpenLogi.upstream.app`.

## What this fork does not do

- No state in the ring: a slot cannot show "recording…", and a failed capture cannot
  toast an error. `Action` is config data and the overlay renders labels, not
  live state; adding that needs an agent-side state probe and an IPC field.
- No automatic skip when Screenflare is missing from `/Applications`: the tool
  reports `app_not_running`, and since the action is detached nobody reads that.
  A `ScreenflareStopRecording` press with nothing recording is likewise a silent
  no-op (`--no-wait` returns before the CLI's `menu_item_disabled`).
- No upstream PR. If this is ever proposed, the ring-state gap above and the
  first-class `screenflare-ctl` dependency are the two review questions.
