# Changelog

All notable changes to **sshCM** ("SSH Config Manager") are documented here, newest first. Each entry corresponds to a [GitHub release](https://github.com/VladGavrila/sshCM/releases).

## [2.1.0] — 2026-07-10

### Added
- **Discover hosts on your network.** A new **Discover** button in the toolbar scans your local network for machines with SSH (port 22) open, so you can add them without hunting for IP addresses. sshCM auto-detects your subnet and prefills the range (e.g. `192.168.1.0/24`), which you can edit before scanning — a CIDR, a start–end range (`192.168.1.1-192.168.1.50`), the last-octet shorthand (`192.168.1.1-50`), or a single IP. Each responder is best-effort reverse-DNS-named to suggest a friendly alias (falling back to the IP when there's no name), with live alias validation and duplicate detection against your existing hosts; any already in your config are flagged. A "Connect as" field (prefilled with your Mac's account name) sets the user applied to every host you add, same as the required User field in the Add Host form. Pick the ones you want and **Add Selected** writes them to `~/.ssh/config` in one step (a single `/etc/hosts` update if that feature is enabled). The scan probes in a bounded concurrency window with a short per-host timeout, and stops the moment you close the sheet.
- **See at a glance which hosts still need key authentication set up.** A reachable host is now checked once per launch to see whether it would let you in on key auth alone; if not, an orange key badge appears on its card/row (and a "Set Up Key Authentication…" entry in its right-click menu) so you can fix it in one click, without having to open Edit first. The check is a real but harmless, non-interactive SSH attempt (it can never prompt for a password or trust an unknown host key) and only ever runs once per host per launch — Refresh and zone switches don't repeat it — so it doesn't add noise to a server's auth logs beyond what a single check requires.

## [2.0.0] — 2026-07-09

### Added
- **Zones.** Group hosts by physical network location — `home`, `work`, `aws`, or whatever you name — and filter the host list down to just one. Unlike color tags, a zone is user-declared (nothing exists by default) and a host belongs to at most one at a time. Manage zones in a new **Settings → Zones** tab: add, rename, drag to reorder, or delete (deleting one clears the assignment from every member host, with a confirmation first). Assign a zone per-host from the Add/Edit sheet or a card/row's right-click menu, or in bulk via "Assign Hosts…" next to each zone in Settings. A toolbar dropdown next to "Show Only Reachable" filters the grid/list to one zone at a time, compounding with search and the reachability toggle; the selection persists across launches. With a zone selected, Refresh only re-probes that zone's hosts. Zones show as a small badge on cards and rows, and are searchable in both the main window and the Command Palette — opening the palette while a zone filter is active carries it over as a dismissible chip (Backspace clears it). The assignment is stored as a `# sshCM-zone: <name>` comment inside the host block, so it round-trips untouched and never affects plain `ssh`; a zone found in a hand-edited config or an imported JSON that isn't yet declared is auto-registered rather than dropped.
- **Sync your config across machines.** A new **Settings → Advanced → Config File Location** section lets you point sshCM at a file in a synced folder (iCloud Drive, Dropbox, Syncthing, …); `~/.ssh/config` becomes a symlink to it, so `ssh`, sshCM, and every other machine read and write the same content while the sync service moves the bytes. Choosing a file with existing content adopts it (your local config is backed up first); choosing an empty location seeds it from your current config. Changes made on another machine are picked up automatically without needing to hit Refresh. A "Revert to Standard…" button turns the config back into a regular file, leaving the synced file untouched.

### Changed
- **Color tags and favorites now live in `~/.ssh/config`,** alongside zones, instead of in the app's private preferences. Each host's color tag and pinned-to-top star are written as `# sshCM-tag: <color>` / `# sshCM-favorite:` comments inside its `Host` block, so they round-trip untouched, never affect plain `ssh`, and travel with the config file (across machines, backups, or version control) rather than being stranded in `UserDefaults`. Existing tags and favorites are moved over automatically the first time you launch this version — nothing to do by hand. The marker always stores the tag's fixed color word (e.g. `green`), never your custom name for it — renaming a tag in Settings, or copying the config to another machine with different names, can't silently orphan a host's tag. **Settings → Host Tag Sort Order** now shows which raw color word each renamed tag maps to, and the tooltip/drag-preview reflect your custom name instead of always showing the default color name. (The tag palette's global order and custom names stay app preferences, since they aren't per-host.)
- **Dropped Intel (x86_64) support.** sshCM now builds and ships as an Apple Silicon-only (arm64) app instead of a universal binary. This is a breaking change for anyone still running sshCM on an Intel Mac — that hardware is no longer supported.

## [1.16.1] — 2026-07-02

### Security
- **Safer auto-update.** Updates are now verified against sshCM's own developer signature *before* anything is installed (previously any validly-signed bundle was accepted, and the download's quarantine flag was cleared before the check even ran). If verification fails, sshCM asks before installing rather than trusting the download silently. The in-place swap during install is also now reversible — a failed update rolls back to the existing app instead of risking leaving none.
- **Imported host files can no longer smuggle in commands.** Importing a hosts file now drops any `ProxyCommand`/`LocalCommand`/`PermitLocalCommand` directive it carries, and reduces its aliases and user names to the same characters the Add/Edit form allows — so a shared export can't run code the first time you connect, and an alias like `-oProxyCommand=…` can't be read by `ssh` as an option.
- **Connect and key-setup now refuse a host alias or user name beginning with `-`,** which `ssh`/`ssh-copy-id` would otherwise treat as a command-line option.

### Fixed
- **A host with an out-of-range `Port` (e.g. a hand-edited `Port 70000`) no longer crashes the app at launch.** Such a value is now left untouched in the config instead of being treated as a usable port.
- **Fewer false "host key changed" warnings.** When `known_hosts` holds more than one key of the same type for a host (a rotated-but-not-removed old key alongside the current one), sshCM now accepts a match against any of them, the way `ssh` itself does.
- **`~/.ssh/config` is never briefly world-readable while saving.** The file is now staged with owner-only permissions before it's swapped into place.

### Improved
- **Update downloads no longer stutter the UI**, and one-shot terminal launch scripts left in the temp folder are now cleaned up instead of accumulating until reboot.

## [1.16.0] — 2026-06-28

### Added
- **Connect via SMB.** A new "Allow SMB" checkbox in Add/Edit Host's Advanced section marks a host as exposing SMB file sharing. When set, a network-drive icon appears before the VNC/terminal buttons on cards and rows, and choosing it opens the host's `HostName` as an `smb://` URL. The flag is stored as a `# sshCM-smb:` comment inside the `Host` block, following the same private-metadata convention as `# sshCM-aliases:` / `# sshCM-vncport:`, so it round-trips untouched and never affects plain `ssh`. In the Command Palette, `⌘B` connects via SMB for an SMB-enabled host (shown as a hint only when applicable).

## [1.15.1] — 2026-06-22

### Fixed
- **Connect via VNC didn't pre-populate the host for TeamViewer or RustDesk.** Both register their own URL scheme rather than accepting a CLI argument, so launching them with the bare IP opened the app with nothing filled in.

## [1.15.0] — 2026-06-21

### Added
- **Remote apps replace the fixed "Host OS" classification for Connect via VNC.** Settings → Apps now has a "Remote Apps" list where you can add any remote-access app (TeamViewer, RustDesk, TigerVNC, RealVNC, …) alongside the always-available, built-in Screen Sharing entry, marked "Default" and not reconfigurable there — add a separate entry instead if you want a different app in that role. The per-host "Host OS" picker in Add/Edit Host's Advanced section is now a "Remote app" picker listing Screen Sharing plus everything configured in Settings. The selection is stored as a `# sshCM-remoteapp:` comment.

### Improved
- **Settings is now organized into tabs** — General, Apps, Tags, Updates, Advanced — instead of one long scrolling form.
- **Settings now stays on top and the main window is non-interactive while it's open**, similar to a native preferences window. Clicking the main window while Settings is up no longer does anything; closing Settings restores normal interaction. An update check triggered from the Updates tab still surfaces its result above Settings instead of behind it.
- **The "connect as/with" menu button now opens its dropdown directly on click**, with the drop-down chevron removed, instead of requiring a separate primary-click-vs-menu distinction.

### Fixed
- **Triggering "Check for Updates…" from the menu-bar status item could leave behind extra, empty main windows.** Several places independently re-derived "the main window" by scanning for a visible, main-capable window; a hidden main window could be missed by that scan and fall through to creating a brand-new one (`openWindow` doesn't deduplicate). The main window is now tracked directly instead of re-scanned.

## [1.14.0] — 2026-06-20

### Added
- **Connect via VNC.** A screen icon, shown only once a host is classified, opens a graphical session — Apple's built-in *Screen Sharing.app* for macOS hosts, or a user-configurable app (e.g. TigerVNC) for Linux hosts, set in **Settings → VNC**. The VNC button appears before the terminal/connect button on cards and rows. Each host is classified manually via a "Host OS" picker (alongside the VNC Port field) in Add/Edit Host's Advanced section — left unset by default, no automatic detection. An optional non-default VNC port can be set per host. Classification and port are stored as `# sshCM-os:` / `# sshCM-vncport:` comments inside the `Host` block, following the same private-metadata convention as `# sshCM-aliases:` / `# sshCM-users:`, so they round-trip untouched and never affect plain `ssh`. In the Command Palette, **⌘↵** connects via VNC for a classified host (shown as a hint only when applicable).

### Improved
- **Automated test coverage for the config round-trip guarantee.** A Swift Package (`Package.swift`) alongside the Xcode project makes the pure Foundation-only model layer runnable. 133 tests across 18 suites cover the parser, serializer, ID-preservation mechanism, ProxyJump alias extraction, semantic version comparison, host list filtering, palette search scoring, `/etc/hosts` block computation, and all sshCM metadata markers.
- **Tab-separated key–value pairs in `~/.ssh/config` are now parsed correctly.** OpenSSH allows tabs as key–value separators (e.g. `HostName\texample.com`). Previously such lines were silently demoted to `rawLines`, causing `HostName`, `User`, `Port`, `IdentityFile`, and `ProxyJump` to be invisible to the UI. They are now parsed on a par with space-separated lines.
- **Host list filter and palette search scoring extracted into testable types.** `ContentView.sortedHosts` (47-line embedded sort/filter/search) has been replaced by `HostListFilter`, a pure struct whose closures accept injected callbacks for favourites, tag ranks, and reachability. `CommandPaletteView.score(host:query:)` has been extracted to `HostSearchScorer`, a stateless enum with an explicit scoring hierarchy (`exact alias 1000 > exact search alias 900 > prefix alias 500+ > …`). Both types live in `Models/` and are covered by the new test suite.
- **`/etc/hosts` block computation split into its own testable type.** The pure functions previously embedded in `HostsFilePublisher` (`managedEntries`, `rebuild`, `isLiteralIP`, `isPublishableHostname`, marker constants) are now in `HostsFileBlock` (Foundation + Darwin only, no AppKit). `HostsFilePublisher` delegates to `HostsFileBlock` for all block logic; the I/O and privilege-elevation paths are unchanged.
- **All UserDefaults keys centralised in `AppStorageKey`.** Fifteen string literals scattered across `FavoritesStore`, `TagsStore`, `HostKeyBypassStore`, `HostsFilePublisher`, `UpdateChecker`, `TerminalLauncher`, `ContentView`, `SettingsView`, and `SeedKeySheet` are now defined once in `AppStorageKey` (a `CaseIterable` `String` enum). A test asserts all 15 keys are unique. All store initializers and `@AppStorage` declarations updated to use the enum.
- **`ConfigStore` accepts an injected config URL for testing.** The hardcoded `~/.ssh/config` path is now a default argument (`init(configURL: URL? = nil)`), leaving runtime behaviour unchanged while enabling isolated test scenarios that do not touch the real config file.

### Fixed
- **Parser no longer treats `Host` inside a `Match` block as an ambiguous case.** The `!inMatchBlock || true` tautology (always `true`) that guarded the `Host` keyword handler has been removed; the condition is now a plain keyword check. Behaviour is identical — `Host` always starts a fresh stanza — but the intent is no longer hidden behind dead code.

## [1.13.1] — 2026-06-19

### Fixed
- **The main window no longer drops behind after an `/etc/hosts` admin prompt.** When adding or removing a host triggered the elevation dialog (Touch ID or the password prompt), dismissing it could leave another app frontmost and push sshCM into the background. sshCM now reclaims focus after the prompt if it was the active app beforehand.
- **sshCM returns to the foreground after key-authentication setup.** When the *Set Up Key Authentication* flow finishes its `ssh-copy-id` / `ssh-keygen` command in Terminal, sshCM now comes back to the front so you see the result (and, after generating a key, the key-selection step) instead of being left on the Terminal window. Focus is only reclaimed once the command actually finishes — not while you may still be entering a password.

## [1.13.0] — 2026-06-19

### Improved
- **Update sheet now shows every version you missed, not just the latest.** When an update is found, the *Update Available* sheet accumulates the release notes for every version between the one you're running and the newest — each under its own heading, newest first — so a user several releases behind sees the full changelog in one place. Single-step updates look exactly as before. Draft and prerelease tags are ignored, and the newest release that ships an installable `sshCM.zip` is still the one installed.

## [1.12.0] — 2026-06-18

### Improved
- Updated app icon
- added `CHANGELOG.md` file for better release review

## [1.11.0] — 2026-06-09

### Added
- **Export & import hosts as a portable JSON file** (toolbar menu, **⌘E** / **⌘I**) for backups or setting up a new Mac. Captures everything sshCM knows about a host — hostname, user, port, identity file, proxy jump, alternate users, search aliases, on-demand port forwards — plus its color tag and favorite state. Only selected hosts are written; global directives and `Match` blocks are left out.
- **Shared picker on both sides**, matching the main window: color-tag stripe, live reachability dot, favorite star, per-row checkbox, instant search filter, **Reachable only** narrowing (imports are probed too), and a **New only** toggle on import to hide already-existing aliases. `Select`/`Deselect All` and export/import act only on currently-visible, checked rows.
- **Host-by-host conflict resolution on import.** For each alias collision: **Use Imported** (replace in place), **Keep Current** (skip), or **Cancel**, with a "1 of 3" progress counter. Brand-new hosts are added without interruption.

### Improved
- **Touch ID for `/etc/hosts` updates** when `pam_tid.so` is configured for `sudo` — authenticate with a fingerprint instead of typing your password; falls back to the usual admin prompt otherwise.

## [1.10.0] — 2026-06-08

### Added
- **On-demand SSH port forwarding.** Attach `-L` (local) and `-R` (reverse) forwards to any host via **Edit → Port Forwarding**, each with a plain-language description. Forwards are saved but stay dormant — a normal connect never opens a tunnel.
- **Pick a tunnel only when you want one.** Hosts with forwards gain a badge (cards, list, palette) and a connect menu offering **local (-L)**, **reverse (-R)**, or **both**. From the palette, **⇧↵** applies local forwards and **⌃↵** reverse ones. Only the forward spec reaches the `ssh` command line.
- Forwards are stored as `# sshCM-localforward:` / `# sshCM-remoteforward:` comments inside the host block (not native `LocalForward`/`RemoteForward`), so `ssh host` from a terminal behaves exactly as before and the metadata round-trips untouched.

### Improved
- **Redesigned "host key has changed" warning** as a native sheet matching the app, replacing the old system alert. Shows the entry and the new key's SHA256 fingerprint, with the same four choices (remove old key, connect once without checking, always bypass, cancel).
- **Offer to re-copy your key after a rebuild.** After removing a stale host key, sshCM offers to re-copy your public key to the host so you aren't locked out on the next connection.

## [1.9.1] — 2026-06-03

### Fixed
- **Hosts that share a name no longer connect to the wrong machine.** Multi-word names (e.g. `test another host`) were split on spaces into separate SSH aliases, causing collisions that crossed up connections, tags, and host-key bypasses. Aliases are now a single, unique token.
- **The Alias field rejects invalid characters as you type** — only letters, digits, and `- . _` are kept; a note explains what was dropped. Saving is blocked (with an inline message) if an alias is already in use. Editing an older multi-word host collapses it to a clean alias on save.
- **The Search aliases field follows the same validation rules** (commas still separate individual aliases).

## [1.9.0] — 2026-05-30

### Added
- **Host key change detection.** After a reachability check, a lightweight `ssh-keyscan` pass (no login, no prompts) compares the server key against `~/.ssh/known_hosts`. Genuinely *changed* keys raise a yellow warning in cards, list, and palette; brand-new hosts stay quiet (trust-on-first-use).
- **Decide what to do at connect time.** Connecting to a flagged host shows the entry and new key's SHA256 fingerprint, with three choices: **Remove the old key** (`ssh-keygen -R`, with a `.old` backup), **Connect once without checking**, or **Always bypass for this host**. Persisted bypasses show an orange unlocked-padlock badge and can be revoked from the host's **Edit** sheet (the bypass follows alias renames).
- **Make aliases resolvable system-wide.** Opt-in **Settings → System-Wide Name Resolution** publishes aliases into a clearly-marked, app-owned `/etc/hosts` block so they resolve everywhere (Screen Sharing, VNC, browsers). Only hosts whose `HostName` is a literal IP are published; macOS prompts for admin only when the published list actually changes.

## [1.8.1] — 2026-05-27

### Fixed
- **Edits from the Command Palette are now saved.** Editing a host from the palette with the main window closed silently discarded the change. Host identity is now preserved across reloads (matched by alias).
- **Keep the terminal open after a session ends.** When `ssh` exits, the tab drops into an interactive login shell (`[sshCM] Session ended — returning to shell.`) so scrollback stays available. Controlled by **Settings → Default Terminal Application → "Keep terminal open after session ends"** (on by default).

## [1.8.0] — 2026-05-23

### Added
- **Alternate users per host.** New *Alternate users* field stored as a `# sshCM-users:` comment. The terminal button becomes a split-button (click = default user, dropdown = alternates). In the palette, **⌥↵** opens a keyboard-driven *Connect as…* picker (↑↓ + ↩, ⌘1–9 direct, Esc to back out); right-click is the mouse equivalent. Key-seeding runs once per newly added alternate user.
- **Card / List view toggle** in the toolbar. The compact list keeps every glyph and control, supports swipe-to-delete, and persists across launches.
- **Show only reachable hosts** toolbar filter, persisted across launches and combinable with search.
- **Type-ahead filter in the main window** — typing anywhere captures into the search field (**Backspace** trims, **Esc** clears); skips when a sheet or text field has focus.
- **Configurable "Show Main Window" hotkey** (Settings → Global Hotkeys), disabled by default. Both hotkeys appear in the menu-bar status menu.
- **Jump-host indicators** — a glyph on hosts used as a `ProxyJump` (card footer, list, palette) and on hosts that go *through* a jump host (palette).
- **Alt-users badge in the palette** (`person.2` pill with count and tooltip); the *⌥↵ Connect as…* hint shows only when the highlighted host has alternates.
- **Default public key for setup** (Settings → *Public Key for Setup*), pre-selected in the *Set Up Key Authentication* sheet.

### Fixed
- Editing/deleting/adding a host from the palette now opens the main window if it was closed (common in menu-bar mode).
- Removed a hard-coded ⌘K palette binding that fired regardless of the configured global hotkey.
- Reachability indicator no longer flickers when filtering — status is read directly from the shared cache.

## [1.7.0] — 2026-05-19

### Added
- **Search aliases.** New comma-separated *Search aliases* field (stored as `# sshCM-aliases:`) makes a host discoverable in the grid and palette under other names without affecting what `ssh <alias>` connects to.

### Fixed
- The Command Palette reserves a stable height (four rows) so it no longer jumps in size as you type.

## [1.6.0] — 2026-05-16

### Added
- **Reachability in the Command Palette** — each result row shows the same colored dot as the main grid.
- **⌘1 – ⌘9 to jump** to a visible result and connect immediately.
- **⌘I to copy IP** (the host's `HostName`, or alias if none); ⌘C still copies the full SSH command.
- **⌘R to refresh the highlighted host** in the palette (pulses orange while probing, updates the shared cache); ⌘R still does a full Reload Config when the palette is closed.
- **⌘N opens the Add Host form**, replacing the default macOS *New Window* binding.

### Fixed
- The Command Palette is rebuilt from scratch on each open, fixing broken arrow keys / shortcuts after dismissing with Esc.

## [1.5.2] — 2026-05-14

### Improved
- **Check for Updates…** added to the menu-bar status dropdown, surfacing the main window so results appear where expected.

## [1.5.1] — 2026-05-14

### Fixed
- Menu bar rebuilds immediately after switching from menu-bar mode back to Dock mode.
- Settings opens reliably from the menu-bar icon (now uses SwiftUI's `openSettings`).

### Improved
- Settings responds to Esc as Cancel.

## [1.5.0] — 2026-05-14

### Added
- **Global hotkey for the Command Palette** (default **⌥K**), rebindable in Settings and toggleable off.
- **Spotlight-style floating palette** — a borderless panel anchored near the top-third of the active screen, dismissing on Esc or focus loss.
- **App keeps running with the main window closed** — the hotkey, menu-bar item, and Dock activation bring it back; ⌘Q fully exits.
- **Dock icon or menu bar icon** — new *App Presentation* section in Settings, switchable live without relaunch. Menu-bar mode adds a dropdown for palette, main window, settings, and quit.

## [1.4.0] — 2026-05-12

### Added
- **Color tags for hosts** — one of seven fixed colors per host, drawn as a 5pt inset border on the card.
- **Assign tags from Add / Edit Host** via a swatch popover; tags are stored per primary alias, migrate on rename, and clear on delete.
- **Tag-aware sorting** — favorites first, then tagged hosts grouped by color, then untagged, alphabetical within each group.
- **Drag-and-drop tag-order in Settings** (*Host Tag Sort Order*) with live re-grouping and *Reset to Default*.
- **Renameable tags** — custom display names (e.g. "Production") used in tooltips, search, and palette matching.
- **Reachability cache** per `host:port` for the session, so filtering no longer re-probes hosts.

### Fixed
- The toolbar *Refresh* button (and ⌘R *Reload Config*) now clears the cache and forces a re-probe.

## [1.3.2] — 2026-05-12

### Added
- **Runs on macOS Sequoia** — deployment target lowered from macOS 26 (Tahoe) to macOS 15 (Sequoia).

### Fixed
- Reachability dots no longer flash straight to red on first launch — the TCP probe now ignores the transient `.waiting` state and resolves on `.ready`, `.failed`, `.cancelled`, or timeout.

## [1.3.1] — 2026-05-11

### Added
- The *Update Available* sheet renders GitHub release notes as proper Markdown.

### Fixed
- `scripts/build-release.sh` no longer hardcodes `BUNDLE_SHORT_VERSION=1.0.0` and override the project's `MARKETING_VERSION`.

## [1.3.0] — 2026-05-11

### Added
- **Key-based authentication setup.** After adding a reachable new host, a *Set Up Key Authentication* sheet offers to seed your public key into the remote's `authorized_keys`. Scans `~/.ssh` for keys (one / multiple / none — with **Generate Key** running `ssh-keygen -t ed25519`), runs `ssh-copy-id`, and reports success, failure (last line of output), or a 30s timeout. **Hide** dismisses without stopping the Terminal command.

## [1.2.0] — 2026-05-10

### Added
- **In-app updates.** New **Check for Updates…** menu item and Settings *Updates* section (auto-check toggle, current version, last-checked time, manual check). The update sheet shows the new version with release notes and offers **Install Update**, **Skip This Version**, or **Remind Me Later**. Auto-checks are throttled to once every 24 hours; skipped versions are remembered until the next user-initiated check.
- Installs verify the downloaded bundle (`ditto` extract, quarantine strip, codesign check), then a helper script swaps the running app and relaunches. Failures keep the sheet open with the error.

## [1.1.0] — 2026-05-10

### Added
- **Host reachability indicator** — a colored status dot per card (orange checking / green reachable / red not), driven by a 5-second TCP probe.
- **Favorites + favorites-first sort** — a star pins hosts to the top, persisted in `UserDefaults` (config untouched).
- **Command palette (⌘K)** — Spotlight-style overlay for keyboard-first connect/edit/copy/delete (`↑/↓` navigate, `↵` connect, `⌘E` edit, `⌘C` copy `ssh <alias>`, `⌘D` delete, `Esc` close) with fuzzy ranking (exact alias > prefix > substring > other field, favorites tie-breaking up).

## [1.0.0] — 2026-05-10

### Added
- Initial release. Reads, edits, and writes `~/.ssh/config`, presenting each `Host` block as a card in a searchable grid:
  - **Browse** every host with alias, hostname, user, port, identity file, and `ProxyJump`.
  - **Filter** across alias, hostname, user, identity file, proxy jump, and port.
  - **Add / edit hosts** (alias, `HostName`, `User`, `Port`, and Advanced `IdentityFile` / `ProxyJump`, with file picking).
  - **Remove hosts** with a confirmation dialog.
  - **Connect** by launching `ssh <alias>` in the configured terminal via a one-shot `.command` script.
  - **Configure terminal** in Settings (defaults to Terminal.app).
- Config handling preserves structure: atomic `0600` writes, `~/.ssh` created `0700` if missing, and comments, blank lines, global directives, `Include`/`Match` blocks, and unknown keys round-trip verbatim.

[2.1.0]: https://github.com/VladGavrila/sshCM/releases/tag/v2.1.0
[2.0.0]: https://github.com/VladGavrila/sshCM/releases/tag/v2.0.0
[1.16.1]: https://github.com/VladGavrila/sshCM/releases/tag/v1.16.1
[1.16.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.16.0
[1.15.1]: https://github.com/VladGavrila/sshCM/releases/tag/v1.15.1
[1.15.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.15.0
[1.14.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.14.0
[1.13.1]: https://github.com/VladGavrila/sshCM/releases/tag/v1.13.1
[1.13.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.13.0
[1.12.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.12.0
[1.11.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.11.0
[1.10.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.10.0
[1.9.1]: https://github.com/VladGavrila/sshCM/releases/tag/v1.9.1
[1.9.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.9.0
[1.8.1]: https://github.com/VladGavrila/sshCM/releases/tag/v1.8.1
[1.8.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.8.0
[1.7.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.7.0
[1.6.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.6.0
[1.5.2]: https://github.com/VladGavrila/sshCM/releases/tag/v1.5.2
[1.5.1]: https://github.com/VladGavrila/sshCM/releases/tag/v1.5.1
[1.5.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.5.0
[1.4.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.4.0
[1.3.2]: https://github.com/VladGavrila/sshCM/releases/tag/v1.3.2
[1.3.1]: https://github.com/VladGavrila/sshCM/releases/tag/v1.3.1
[1.3.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.3.0
[1.2.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.2.0
[1.1.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.1.0
[1.0.0]: https://github.com/VladGavrila/sshCM/releases/tag/v1.0.0
