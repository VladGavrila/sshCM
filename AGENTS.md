# AGENTS.md — sshCM

Guidance for AI agents (and humans) maintaining and extending this repository.

## What this is

**sshCM** ("SSH Config Manager") is a native macOS app, written in **SwiftUI + AppKit**, that gives `~/.ssh/config` a graphical front end. It reads, edits, and writes the user's real OpenSSH client config, presenting each `Host` block as a card (or list row) in a searchable window. From the UI a user can browse, filter, add, edit, and remove hosts, launch `ssh` sessions in their terminal of choice, see live host reachability, and get warned about changed SSH host keys.

It is a single-user, local-only desktop utility. There is no backend, no network service of its own (only an outbound GitHub call for self-update), and no test target.

- Bundle ID: `com.vgdev.sshCM` · Display name: "SSH Config Manager"
- Min OS: **macOS 15.0** · Swift 5.0 · Apple Silicon only (`ARCHS = arm64`, built via `generic/platform=macOS`)
- Distribution: Developer ID-signed, notarized `.app`, shipped via GitHub Releases. The app self-updates.

## Repository layout

```
sshCM/                      ← repo root
├── README.md               ← user-facing description
├── AGENTS.md / CLAUDE.md   ← this file (CLAUDE.md is a symlink to AGENTS.md)
├── scripts/
│   ├── build-release.sh    ← THE build/sign/notarize entry point
│   └── ExportOptions.plist  ← developer-id export template (__TEAM_ID__ substituted at build)
├── release-notes/          ← per-version markdown (vX.Y.Z.md), source for GitHub release bodies
├── dist/                   ← build output (gitignored): sshCM.app + sshCM.zip
├── .build/                 ← DerivedData + xcarchive (gitignored)
└── sshCM/                  ← the Xcode project lives one level down
    ├── sshCM.xcodeproj     ← project (scheme: sshCM)
    └── sshCM/              ← all Swift source
        ├── sshCMApp.swift   ← @main App, AppDelegate, environment wiring, global commands
        ├── ContentView.swift← main window: grid/list, search, sheets, reachability orchestration
        ├── Models/          ← pure data + parsing (no UI, mostly no AppKit)
        ├── Stores/          ← @Observable state holders (the "view models")
        ├── Utilities/       ← side-effecting helpers (ssh, terminal, /etc/hosts, updates, hotkeys)
        └── Views/           ← SwiftUI views and the command-palette NSPanel host
```

Note the **double `sshCM/sshCM/`** nesting: the project file is at `sshCM/sshCM.xcodeproj`, sources are at `sshCM/sshCM/`. Paths in build commands must account for this.

## Architecture

### Data model & the round-trip guarantee (the heart of the app)

The single most important invariant: **sshCM must never corrupt or lose parts of a user's `~/.ssh/config`.** The parser/serializer is built around preserving everything it doesn't explicitly understand.

- `Models/SSHConfigFile.swift` — a config file is an ordered array of `SSHConfigBlock`, each either `.host(SSHHost)` or `.raw(String)`. Comments, blank lines, global directives, `Include` lines, and entire `Match` blocks are kept **verbatim** as `.raw`. `serialize()` reproduces the file; `add`/`remove`/`update` mutate by `id`.
- `Models/SSHHost.swift` — one `Host` block. Only the well-known keys (`HostName`, `User`, `Port`, `IdentityFile`, `ProxyJump`) are surfaced as typed, editable fields. **Any other line inside a host block round-trips untouched via `rawLines`.**
- `Models/SSHConfigParser.swift` — line-based parser. `Key Value` and `Key=Value` both supported; values may be quoted. Unknown keys → `rawLines`. `Match` blocks → raw. A `Host` line always starts a fresh block.
- `Models/HostTag.swift` — the 7-color tag enum (UI-only metadata, not an SSH concept).

**sshCM-private metadata is stored as structured comments** inside host blocks so it survives in plain `~/.ssh/config` without breaking `ssh`:
- `# sshCM-aliases: a, b, c` → `searchAliases` (extra search-only names)
- `# sshCM-users: root, deploy` → `alternateUsers` (extra users offered in the "connect as" menu)
These markers are defined in `SSHConfigParser` (`searchAliasesMarker`, `alternateUsersMarker`) and emitted by `SSHConfigFile.serializeHost`.

**ID preservation across reload:** `SSHConfigFile.preserveIDs(from:)` reuses prior `UUID`s (matched by primary alias) when reparsing, so a host reference captured before a reload (e.g. a host being edited from the command palette) isn't orphaned. `ConfigStore.load()` calls this on every load.

**Aliases are single tokens.** Each `Host` alias is one whitespace-free token (validated on input — only letters, digits, `- . _`). Tags, favorites, and host-key bypasses are all keyed by the **primary alias** (`aliases.first`), so alias uniqueness matters for correctness.

### State: `@Observable` stores (the "view models")

Stores live in `Stores/`, are `@MainActor @Observable final class`, instantiated once in `sshCMApp` as `@State`, and injected via `.environment(...)`. Views read them with `@Environment(StoreType.self)`.

| Store | Responsibility | Persistence |
|---|---|---|
| `ConfigStore` | Load/save `~/.ssh/config`; the source of truth for hosts | the file itself (atomic, `0600`) |
| `FavoritesStore` | Favorite aliases (sort to top) | `UserDefaults: favoriteAliases` |
| `TagsStore` | Per-alias color tag, tag order, custom tag names | `UserDefaults: hostTags / hostTagOrder / hostTagNames` |
| `ReachabilityCache` | TCP reachability + host-key status per `host:port`, keyed by `cacheKey` | in-memory only (epoch-based invalidation) |
| `HostKeyBypassStore` | Aliases the user chose to permanently skip strict host-key checking | `UserDefaults: hostKeyBypassAliases` |
| `PaletteBridge` | One-shot signals from the command palette to `ContentView` (`pendingEdit/Delete/Add`) | none (transient) |
| `UpdateChecker` | GitHub release polling, download, install orchestration; a state machine | `UserDefaults` (last check, skip, auto-check) |

`ConfigStore` is the only store that owns durable data outside `UserDefaults`. All writes go through `add/remove/update`, which `persist()` to disk and then call `publishHostsIfEnabled()`.

### Key utilities (`Utilities/`)

- **`HostConnector`** — single entry point for "connect to host", shared by the main window and the command palette. Centralizes the host-key gate: persisted bypass → connect with checking off; changed key → open remediation dialog; otherwise connect normally. Always go through this, not `TerminalLauncher` directly, when launching a user session.
- **`TerminalLauncher`** — writes a one-shot `…/sshcm-<uuid>.command` bash script (`0755`) and `open`s it with the configured terminal app via `NSWorkspace`. Aliases/users are single-quote-escaped. `keepTerminalOpenAfterSession` controls whether the shell stays open after `ssh` exits.
- **`Reachability`** — async TCP connect probe via `Network.framework` (`NWConnection`), 5s timeout. No data sent.
- **`HostKeyVerifier`** — compares server-presented keys (`ssh-keyscan`) against `known_hosts` (`ssh-keygen -F`). Only a genuine per-type **mismatch** is `.changed`; unknown/first-use/cert/stale cases never warn. No auth, so it never triggers password prompts. `removeStoredKey` runs `ssh-keygen -R`.
- **`HostKeyRemediation`** — the AppKit alert offering remove-offending / bypass-once / bypass-persist / cancel.
- **`HostsFilePublisher`** — optional feature: mirrors hosts whose `HostName` is a literal IP into a marked block in `/etc/hosts` (so aliases resolve in Screen Sharing, browsers, etc.). Writes need root, done via one `osascript … with administrator privileges` prompt — and **only when the managed block actually changes** (no needless prompts). Block-computation functions are pure and testable. Gated by `UserDefaults: publishAliasesToHostsFile`.
- **`UpdateChecker` + `AppInstaller` + `SemanticVersion`** — self-update. Polls `api.github.com/repos/VladGavrila/sshCM/releases` (overridable via the `SSHCM_RELEASES_API` env var for local E2E testing) for a `sshCM.zip` asset, streams the download with progress, verifies the signer is pinned to the project's Developer ID team (not just "is it signed at all"), then hands off to a detached installer script that waits for the app to quit, swaps the bundle (rolling back on failure), and relaunches. If the signer doesn't match, `UpdateChecker` surfaces a `.confirmUnsigned` state instead of installing silently — the user must explicitly accept before an unsigned build is used. The install side is injected as an `UpdateInstalling` (live: `LiveUpdateInstaller` → `AppInstaller`; tests inject a fake), and the download→verify→install/confirm seam is `installDownloaded(_:release:)` — so the state machine is unit-tested without a real signed bundle. `UpdateInstalling` + `UpdateChecker` are Foundation-only and live in the `sshCMUtilities` SPM target; `AppInstaller` (AppKit-bound: `codesign`/`ditto`/`NSApplication`) stays in the Xcode app target only.
- **`GlobalHotKey` + `KeyShortcut`** — Carbon `RegisterEventHotKey` global shortcuts. Two definitions: **palette** (default ⌥K, enabled) and **mainWindow** (default ⌥S, disabled). Settings keys live in `KeyShortcut.Definition`.
- **`AppPresentation` + `MenuBarStatusItem`** — toggle between Dock app (`.regular`) and menu-bar accessory (`.accessory`). The menu-bar item rebuilds its `NSMenu` and reflects current hotkeys.
- **`PublicKeyDiscovery`** — lists `~/.ssh/*.pub`, used by the key-seeding flow.

### Notable UI pieces (`Views/`)

- `ContentView` — owns search (`searchText`, with a type-ahead `NSEvent` monitor that captures keystrokes into the filter), grid vs list mode, the "show only reachable" filter, all the sheets/alerts, reachability probe orchestration (`probeFleetKey` task), and draining `PaletteBridge`.
- `HostCardView` / `HostRowView` — the two host presentations; both take the same `onEdit/onDelete/onConnect/onConnectAs` closures.
- `AddHostSheet` — add/edit form with alias validation and Advanced fields.
- `CommandPaletteController` + `CommandPalettePanel` + `PalettePanelContent` + `CommandPaletteView` — a Spotlight-style floating `NSPanel` (non-activating, modal level, closes on resign-key) hosting a SwiftUI search/launch UI. Driven by the global hotkey; talks back to the app through closures configured in `sshCMApp.configurePalette()` and the `PaletteBridge`.
- `SeedKeySheet` — after adding a host (or a new alternate user) that's reachable, offers to copy a public key to it (`ssh-copy-id`-style) so the user can log in without a password. Uses `PublicKeyDiscovery`.
- `SettingsView` — the `Settings` scene: terminal app, presentation mode, hotkeys, `/etc/hosts` publishing, auto-update.

### Cross-component wiring quirks

Because parts of the app (menu-bar item, command palette `NSPanel`) live outside the SwiftUI window/environment, several `static var` "trigger" closures bridge them back into SwiftUI actions, set up in `ContentView.onAppear`:
- `MainWindowOpener.open`, `SettingsOpener.open`, `UpdateCheckTrigger.trigger` (in `MenuBarStatusItem.swift`).
- The command palette is configured in `sshCMApp.configurePalette()` with closures that call `HostConnector`, surface the main window, and set `PaletteBridge` flags.

When adding a feature that must be reachable from both the main window and the menu-bar/palette, follow this pattern rather than reaching into SwiftUI state directly.

## Building & running

There is **no SPM, no test target, no CI config in-repo.** Building requires **full Xcode** (not just Command Line Tools).

### Canonical build (what the user actually tests)

```bash
./scripts/build-release.sh          # run from repo root
```

This archives a **Release** build, ad-hoc signs when no Developer ID env vars are present, and produces `dist/sshCM.app` + `dist/sshCM.zip`. It auto-sets `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when `xcode-select` points at CommandLineTools. Takes a few minutes — **raise the Bash timeout**. The user runs `dist/sshCM.app`, so editing source without rebuilding won't change what they see.

### Fast Debug build (for compile-checking changes)

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project sshCM/sshCM.xcodeproj -scheme sshCM -configuration Debug \
  -derivedDataPath .build/DerivedData -destination 'generic/platform=macOS' \
  build CODE_SIGNING_ALLOWED=NO
```

Output lands at `.build/DerivedData/Build/Products/Debug/sshCM.app`.

### Running a freshly built copy

macOS won't launch a second instance with the same bundle ID. To test:
```bash
osascript -e 'quit app "sshCM"'; pkill -f sshCM.app   # stop the running copy first
open .build/DerivedData/Build/Products/Debug/sshCM.app
```

### Quick logic checks without the full app

The pure model files (`SSHHost.swift`, `SSHConfigFile.swift`, `SSHConfigParser.swift`) compile standalone with `swiftc` (also needs `DEVELOPER_DIR`) — handy for exercising parser/serializer logic in isolation.

> **SourceKit caveat:** in-editor "Cannot find type X in scope" diagnostics are often spurious (files analyzed without module context). Trust the `xcodebuild` result, not isolated diagnostics.

## Release process

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION` if needed) in the project — or pass `BUNDLE_SHORT_VERSION` / `BUNDLE_VERSION` env vars to the build script.
2. Write `release-notes/vX.Y.Z.md` (this becomes the GitHub release body, rendered in-app by `MarkdownView`).
3. Run `build-release.sh` **with signing/notarization env vars** set:
   `DEVELOPER_ID_CERT_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`, `NOTARIZE_APPLE_ID`, `NOTARIZE_TEAM_ID`, `NOTARIZE_APP_PASSWORD` (team defaults to `2RZL73M634`). It imports the cert into a temporary keychain, archives with `--timestamp --options=runtime`, exports developer-id, notarizes (`notarytool --wait`), and staples.
4. Create the GitHub release tagged `vX.Y.Z` with `sshCM.zip` attached as an asset named exactly **`sshCM.zip`** (the updater looks for that name). Tag must parse as a semver (`SemanticVersion`).

Commits in this repo are tagged-release snapshots (`git log` shows `X.Y.Z release` commits on `main`).

## Testing

There **is** now a lightweight Swift Testing target, separate from the Xcode app target: `Package.swift` at the repo root compiles the pure, Foundation-only model/utility files (listed explicitly under `sshCMModels`/`sshCMUtilities` targets) into library targets, and `Tests/sshCMTests/` covers them with `@testable import sshCMModels`/`sshCMUtilities`.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # from repo root
```

- **Run the suite before making changes**, to confirm your starting point is green, and **again after**, to confirm nothing broke — `swift test` is fast (well under a second) so there's no excuse to skip either side.
- **Add or update tests for any new/changed functionality that lives in a file already listed in `Package.swift`** (currently: `SSHHost`, `SSHConfigFile`, `SSHConfigParser`, `PortForward`, `HostListFilter`, `HostSearchScorer`, `HostsFileBlock`, `AppStorageKey`, `SemanticVersion`, `UpdateInstalling`, `UpdateChecker`, `ConfigLocation`, `ConfigFileWatcher`). Follow the existing per-type `@Suite`/`@Test` structure in `Tests/sshCMTests/` (e.g. `ParserTests.swift` has `Parsing` / `sshCM metadata markers` / `Round-trip` suites — mirror that shape for new markers or fields).
- If a new pure, Foundation-only file is added to `Models/` or `Utilities/` and deserves coverage, add it to the relevant target's `sources` list in `Package.swift` first.
- Files that depend on AppKit/SwiftUI/Network or other non-Foundation frameworks (most of `Utilities/` and all of `Views/`/`Stores/`) aren't part of the SPM package and can't be unit tested this way — verify those by building and running the app per the section above. `UpdateChecker`'s install/confirm state machine is the exception: it's unit-tested with a fake `UpdateInstalling` (`UpdateCheckerTests`), even though the app injects the real `AppInstaller`-backed one. Its network fetch and `AppInstaller` itself (codesign, ditto, subprocess swap) are still verified manually — via `scripts/test-updater-e2e.sh [signed|adhoc]`, which serves a crafted release + `sshCM.zip` from a local `http.server` and launches the app with `SSHCM_RELEASES_API` set, so the full download→parse→verify→install/opt-in flow can be driven without publishing to GitHub. The signer-pinning requirement itself can be checked directly with `codesign --verify --deep --strict -R=…` against ad-hoc vs Developer-ID-signed bundles.
- A new `AppStorageKey` case requires bumping the expected count in `AppStorageKeyTests.keyCountMatchesExpected()` and adding its raw-value assertion — the test deliberately fails loudly on any unannounced add/remove.
- This complements, not replaces, **manual verification by building and running the app** (see above) — `swift test` only covers the pure model/utility layer, not UI wiring, AppKit integration, or the full save/connect/launch flows.

## Keeping CHANGELOG.md current

**Every user-visible change must be reflected in `CHANGELOG.md`.** This includes follow-up fixes/tweaks made within the same conversation — don't leave the entry describing behavior that's since changed; update it in place rather than appending a near-duplicate bullet.

- Before adding or amending an entry, **ask the user which version this work belongs to** (a new release, or a fix folded into the version still in progress) — don't guess or default to bumping automatically.
- If the user names a new version, bump `MARKETING_VERSION` in `sshCM/sshCM.xcodeproj/project.pbxproj` (both build configurations) to match, and add a new `## [X.Y.Z] — <date>` section plus its link reference at the bottom of the file.
- If the work folds into the version already at the top of the file, edit that section's existing bullets directly so they describe the current behavior.

## Conventions & gotchas

- **Swift style:** `@MainActor @Observable final class` for stores; `enum` namespaces for stateless utilities (`TerminalLauncher`, `HostKeyVerifier`, `Reachability`, …); `nonisolated` + `Task.detached` for blocking subprocess/IO work off the main actor. Match the surrounding file's comment density — this codebase comments the *why*, especially around security and edge cases.
- **Security model is deliberate.** Host-key bypass weakens security and is only ever set through the explicit remediation dialog. `/etc/hosts` writes are elevated and minimized. Preserve these guardrails; don't add silent bypasses.
- **Never lose config data.** When touching the parser/serializer, keep unknown keys, comments, `Match`/`Include`, and ordering intact. The round-trip (parse → serialize) of an untouched file must be a no-op modulo the trailing newline.
- **Symlink write-through invariant.** `~/.ssh/config` may be a symlink into a synced folder (`Utilities/ConfigLocation.swift`). Anything that writes the config file must resolve through the link and write the *target*, not the link node itself — `FileManager.replaceItemAt` on a symlink path replaces the link, silently breaking sync. `ConfigStore.persist()` goes through `ConfigLocation.writeTarget(for:)`; keep any new config-writing code consistent with that.
- **UserDefaults keys are an informal API** (they're also read in places via raw string literals, e.g. `defaultTerminalAppPath`, `defaultPublicKeyPath`). Don't rename without grepping for every literal use.
- **App is not sandboxed** (`ENABLE_APP_SANDBOX = NO`) and uses **hardened runtime** — it needs to read/write `~/.ssh`, run `/usr/bin/ssh*`, write `/etc/hosts` (elevated), and replace its own bundle. Keep that in mind before assuming sandbox-style file access.
- **Automated tests exist for the pure model/utility layer** (see Testing above) but not for UI/AppKit code. For those, verify changes by building and running the app, exercising the affected flow.
- The `.claude/settings*.json` files pre-allow the common `xcodebuild` invocations.
