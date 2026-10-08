# Codex Aura

[简体中文](README.md)

**Codex quota, at a glance.** A native macOS menu bar panel by **CC · [@xunxunmimi](https://github.com/xunxunmimi)**, with an energy ring, reset countdown and daily token estimates.

## Download and install

Updated **2026-10-08 (Asia/Shanghai)**. Latest: **0.4.6 experimental prerelease**.

| Package | Updated | Architecture / system | Download |
| --- | --- | --- | --- |
| `Codex Aura 0.4.6 Universal.dmg.zip` | 2026-10-08 | arm64 + x86_64; macOS 14+; Intel / macOS 14 runtime untested | [Latest experimental build](https://github.com/xunxunmimi/CodexAura/releases/download/v0.4.6-experimental/Codex.Aura.0.4.6.Universal.dmg.zip) |
| `Codex Aura 0.4.1 Universal.dmg.zip` | 2026-10-07 | arm64 + x86_64; macOS 14+; Intel / macOS 14 runtime untested | [Previous experimental build](https://github.com/xunxunmimi/CodexAura/releases/download/v0.4.1-experimental/Codex.Aura.0.4.1.Universal.dmg.zip) |
| `Codex Aura 0.4.0 arm64.dmg.zip` | 2026-10-05 | Apple silicon; macOS 26 isolated startup checked | [Previous experimental build](https://github.com/xunxunmimi/CodexAura/releases/download/v0.4.0-experimental/Codex.Aura.0.4.0.arm64.dmg.zip) |

0.4.6 retains the reviewed 0.4.0 privacy defaults and account-isolated history. It adds native menu-bar placement with fallback access, newer bundled Codex path discovery, low-quota alerts, reset-credit expiry details, quota-window switching and latest-post-only radar scoring. Builds are ad-hoc signed, not notarized; fresh-Mac installation and Intel execution remain untested.

Download the [latest experimental Release](https://github.com/xunxunmimi/CodexAura/releases/tag/v0.4.6-experimental) and [SHA-256 file](https://github.com/xunxunmimi/CodexAura/releases/download/v0.4.6-experimental/SHA256SUMS-0.4.6.txt). Unzip the ZIP to obtain the DMG, then drag the app to Applications. Privacy options remain off by default. Source ZIPs require compilation.

**Missing icon on macOS 26?** Open System Settings → Menu Bar → Allow in the Menu Bar, enable `Codex Aura`, then quit and reopen the app. A fallback window does not necessarily mean the menu bar is full. The in-app restore button cannot override this system switch. [Apple instructions](https://support.apple.com/en-me/guide/mac-help/mchlad96d366/mac)

Licensed under **PolyForm Noncommercial 1.0.0**: source-available for the purposes permitted by the license; commercial uses need separate permission. This is not an OSI open-source license. Read [LICENSE](LICENSE), [NOTICE](NOTICE) and [third-party notices](THIRD_PARTY_NOTICES.md).

> **Experimental prerelease 0.4.6.** Universal release build, personal-path scan, signature integrity, DMG checksum and ZIP integrity checks passed. The merged source passed 27 offline XCTest cases using full Xcode. No real account was contacted. Fresh-Mac installation, real-account use, Intel runtime, macOS 14 and multi-screen UI remain untested.

This independent project is not affiliated with, sponsored by, or endorsed by OpenAI, ChatGPT, Codex, X or Google. Names and trademarks belong to their respective owners.

## 0.4.6 changes (2026-10-08, Asia/Shanghai)

- Stop background menu-bar checks from toggling the Dock icon. Show it only for an explicitly opened fallback window; hide it when that window closes or the normal popover opens.

- Remove the detached fallback icon; fix notch geometry detection and preserve native ordering. Reopen the app manually for a fallback window when the native anchor is unavailable.
- Wait for native menu-bar layout and attempt one bounded recovery. Seed an initial right-side position hint while preserving subsequent ⌘-drag ordering. Add restore and minimal icon-diagnostic buttons to the fallback window.
- Document the macOS 26 menu-bar visibility switch. A user confirmed that enabling it restored the icon on 26.5.1; this is not a general multi-screen compatibility guarantee.
- Allow 25 seconds for quota responses within a bounded 45-second connection; deduplicate errors.
- Retain last successful in-memory quota on same-account partial failure with a stale label. Never reuse quota across verified different accounts. Initialization timeouts explicitly state the current account is unverified.
- Do not trigger low-quota alerts or reuse reset credits from stale results. 27 offline regression tests passed.

## Features

- Menu bar energy ring, actual quota-window labels and reset countdown. Only a returned seven-day window is labeled weekly.
- Today / yesterday tokens with a source label. Missing values are “—”, not zero.
- Selectable reference USD estimate, not an actual bill or official price.
- Native menu bar ordering with ⌘-drag repositioning; manually reopen the app for a fallback window when no usable native anchor exists; the Dock icon is shown only while that window is open.
- “CC · Settings & About” author credit and privacy controls (current UI is mainly Chinese).
- Existing experimental Tibo radar and translation remain available but are **off by default**. Radar shows a keyword score, not a reset probability.

## Requirements

macOS 14+, a separately installed compatible Codex executable signed in with ChatGPT and eligible account usage, and network access for Codex's services. API-key authentication alone is not a replacement for subscription quota access.

The simple build targets the host architecture; the distribution script targets arm64 + x86_64 Universal 2. Universal construction was checked; Intel execution remains untested. The scripts use ad-hoc signing, not Developer ID or notarization. Building needs Swift tools 5.10+, Xcode/macOS SDK and Python 3; minimum working Xcode and real Codex version bounds have not been established. On 2026-10-04, Swift 6.2 compiled the Debug app and passed 14 offline XCTest cases on Apple silicon with synthetic data and mock subprocesses. Neither the real app nor Codex was launched, and no real account was contacted. There were no source compiler warnings; SwiftPM warned that its user cache was not writable in the isolated environment. Native arm64 Release packaging has also completed. SDK debug-module path mapping emitted linker notices; bundle path scanning and signature integrity passed. Browser download/Gatekeeper acceptance remains untested.

## Install and use

**[Experimental Release](https://github.com/xunxunmimi/CodexAura/releases/tag/v0.4.6-experimental).** Its notes identify the source revision, architecture, signing status, SHA-256 checksums and limits. A source ZIP is not a runnable app.

To try this experimental package:

1. Install and sign in to compatible Codex. Codex Aura neither bundles Codex nor requests your credentials.
2. Download its DMG/ZIP and check the supplied SHA-256.
3. Move `Codex Aura.app` to Applications and open it.
4. Click the menu bar ring. Normally no Dock window; a draggable fallback window is available when the menu-bar anchor is inaccessible.
5. Expand daily statistics and inspect their source. Refresh syncs usage; the power button quits.
6. Settings can enable local-log estimates, radar and public-post translation. All three start disabled; collapsing a card does not disable a feature.

Gatekeeper can block an ad-hoc package. After confirming its source and integrity, consult [Apple's instructions](https://support.apple.com/en-us/102445) for “Open Anyway” in System Settings → Privacy & Security. Managed Macs may forbid overrides. Stop on malware/damage warnings rather than treating them as ordinary setup issues.

This candidate does not bundle a quarantine-removal helper or lower system security settings. [Developer ID and notarization](https://developer.apple.com/developer-id/) are separate distribution steps that have not been implemented.

## Build

Use a trusted source root and the tools listed above. No external SwiftPM dependencies are declared.

```bash
cd CodexAura
swift test --jobs 2
./scripts/build_app.sh
```

The native release script requires at least 3 GiB free and produces `dist/Codex Aura.app`. It generates the icon, includes license notices, strips debugging symbols, checks for personal absolute paths, then ad-hoc signs and verifies the app.

```bash
./scripts/build_release_dmg.sh
```

The default distribution build is Universal 2 (minimum 4 GiB), with Finder styling. For a native package without Finder automation (minimum 3 GiB):

```bash
./scripts/build_release_dmg.sh ./dist native plain
open "dist/Codex Aura.app"
```

For Universal 2 without Finder styling, use `./scripts/build_release_dmg.sh ./dist universal plain`. Output is a DMG and a ZIP containing that DMG, plus `SHA256SUMS-<version>.txt`; binaries belong in Releases, not source history. Native filenames identify the host architecture. 0.4.6 offers Universal 2; Intel runtime remains untested. Thresholds are guards, not space guarantees.

Building needs compatible Xcode or Command Line Tools/macOS SDK, Swift tools 5.10+ and Python 3.8+. Only Xcode SDK 26.0 / Swift 6.2 / Python 3.9.6 has been used here. Check `xcode-select -p`, `xcrun --show-sdk-version`, `swift --version`, `python3 --version` and `uname -m`. Complete Apple tool installation first; a Command Line Tools-only setup is untested. The repository root contains Package.swift. `swift build` alone does not produce a full app bundle. A custom `DEVELOPER_DIR` can select a toolchain for one command without global changes.

An optional first argument specifies a dedicated output directory; matching names are replaced. The third argument `plain` avoids Finder automation; `finder` can require build-time Automation permission. Scripts neither launch the app nor submit notarization. Stop if space guards fail. Missing quota/daily values remain “—”; check trusted Codex location, account eligibility and compatibility without broadening permissions. See [Apple's Gatekeeper guidance](https://support.apple.com/en-us/102445); do not remove quarantine or lower security settings.

The client starts `codex app-server` using default stdio and documented read-only requests, without experimental API opt-in. Availability depends on the installed version; [published protocol documentation](https://learn.chatgpt.com/docs/app-server) is not a compatibility test of every local installation.

## Executable and data location

An explicit `CODEXAURA_CODEX_PATH` takes precedence. Otherwise discovery checks bundled Codex, bundled ChatGPT, common Homebrew locations, `~/.local/bin/codex`, then absolute directories in the process PATH. Installing ChatGPT alone does not establish compatibility.

Exactly one Codex home is selected: inherited nonempty `CODEX_HOME`, otherwise `~/.codex`. RPC and optional session parsing use that same home. Finder normally does not inherit terminal variables. To use a custom executable, launch the app executable directly from a configured terminal, for example:

```bash
CODEXAURA_CODEX_PATH=/absolute/path/to/codex \
  "/Applications/Codex Aura.app/Contents/MacOS/CodexAura"
```

Point only to a trusted executable. The app does not log you in, change Codex settings or request new account permissions.

## Privacy

- Quota and daily activity come from local app-server. `account/read` supplies an account ID or email used in memory to calculate a history key. The raw identifier is not persisted.
- UserDefaults stores up to 14 daily buckets per SHA-256 key of selected home and account identifier. This is a hashed identifier, not a promise of irreversible anonymity. Old unscoped history is ignored. Missing identity disables account-history reads/writes.
- Local session estimates are off by default. When enabled, recently modified session JSONL in the selected home is streamed with limits on line size, file count and total bytes. Only token events are decoded, but file bytes can contain conversations/code/paths. Logs are not uploaded.
- Radar is off by default. Enabling it contacts public X pages; X can receive IP, timing and User-Agent. An ephemeral session disables cookie storage and URL cache.
- Translation is off by default. Enabling it sends public post text to Google's `translate_a/single` web endpoint. This project makes no Cloud Translation API support claim for it.

No app code directly reads `auth.json`, Keychain or browser cookies. There is no author collection server, advertising or telemetry SDK. **Codex itself can read its credentials/configuration, refresh authentication, contact services and log activity.** The process chain is not entirely offline or credential-free.

Usage refreshes every five minutes. Scheduled radar refreshes use a thirty-minute condition; opening the panel or manually syncing usage does not bypass it. Changing radar/translation settings can trigger an update. Switching log estimates immediately retries a cancelled in-flight radar fetch; a completed fetch keeps its normal interval. Disabling cancels the active radar request and gates subsequent post/translation requests; cancellation cannot recall data already received by a third party. Results from obsolete settings are discarded.

UserDefaults also holds switches, the reference price, ring position and panel state. Removing the app can leave these preferences. Do not delete Codex authentication or the whole `.codex` directory to uninstall this tool. No camera, microphone, Screen Recording or Accessibility permission is requested; do not grant Full Disk Access blindly.

## Accuracy and limits

- Quota and daily activity degrade independently. An unsupported daily endpoint no longer hides successful quota. Raw server errors/stderr are discarded; the UI uses request names and error codes.
- The `codex` quota bucket is preferred and its longest window shown with its returned duration. This is not comprehensive support for all metered buckets.
- Daily values prefer valid server buckets, preserving explicit zero. Missing buckets may use previously observed same-home/same-account history, then opt-in local estimates. Sources are not added together or merged by taking their maximum.
- Session directories can contain several accounts, missing or duplicate records, and evolving formats. Local values are labeled as folder estimates, not verified account bills. Repeated cumulative counters are not counted twice; missing totals stay unknown.
- USD is `tokens / 1,000,000 × selected rate`, without model/input/output/cache distinctions. It is not a subscription charge or official current price.
- Radar depends on X HTML and applicable usage terms; translation uses a third-party web endpoint. Both can fail. Missing real-time data is explicit; no old sample post is presented as a cache. Keep these features off unless their terms and content permissions have been assessed.
- Requests and pipe output are bounded. Failed refreshes do not present old successful quota as current. Local Codex/network/system-policy incompatibilities remain possible.
- Real accounts, Intel hardware, notch/multi-display UI and browser-download Gatekeeper installation have not been accepted. No notarization or “download and run everywhere” promise is made.

## Feedback, attribution and license

After publication, Issues/PRs can include OS, architecture, Codex version, reproduction steps and redacted screenshots. Never post credentials, `auth.json`, raw sessions/logs, cookies, account IDs, emails or company paths. See [CONTRIBUTING](CONTRIBUTING.md) and [SECURITY](SECURITY.md).

Retain copyright and Required Notice on redistribution as required by LICENSE. Project licensing does not cover third-party services, content or trademarks. Contact the author through their published GitHub contact options about commercial permission; the full license defines permitted purposes and exceptions. This explanation is not legal advice. Visible CC credit identifies the author; it cannot prevent copying.

## Enjoying it? Leave a Star ⭐

If Codex Aura saves you a window switch or makes your remaining quota easier to check, a Star would mean a lot. Suggestions and bug reports are welcome too. Thanks for supporting this little tool!
