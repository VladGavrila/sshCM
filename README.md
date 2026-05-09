# sshCM

A native macOS SwiftUI app for managing your `~/.ssh/config` file with a graphical interface.

## Download

A signed, pre-built version is available from the [Releases](https://github.com/VladGavrila/sshCM/releases) page — no Xcode build required.

## What it does

sshCM reads, edits, and writes your existing OpenSSH client config, presenting each `Host` block as a card in a searchable grid. From the UI you can:

- **Browse hosts** — every `Host` entry in `~/.ssh/config` is shown as a card with its alias, hostname, user, port, identity file, and `ProxyJump`.
- **Filter** — the search bar matches across alias, hostname, user, identity file, proxy jump, and port.
- **Add / edit hosts** — a sheet captures alias, `HostName`, `User`, `Port`, and (under Advanced) `IdentityFile` and `ProxyJump`. Identity files can be picked from disk.
- **Remove hosts** — with a confirmation dialog.
- **Connect** — clicking the terminal icon launches `ssh <alias>` in your configured terminal app via a one-shot `.command` script.
- **Configure terminal** — Settings lets you choose which terminal application to launch (defaults to `Terminal.app`); the choice is persisted via `@AppStorage`.

## How it handles your config

- Reads from and writes to `~/.ssh/config` directly. The file is saved atomically with `0600` permissions, and `~/.ssh` is created with `0700` if it doesn't exist.
- The parser preserves the structure of the file: comments, blank lines, global directives, `Include` lines, and `Match` blocks are kept verbatim as raw blocks. Unknown keys inside a `Host` block are also preserved.
- Only the well-known keys (`HostName`, `User`, `Port`, `IdentityFile`, `ProxyJump`) are surfaced as editable fields; everything else round-trips untouched.

## Building

Open [sshCM/sshCM.xcodeproj](sshCM/sshCM.xcodeproj) in Xcode and build the `sshCM` scheme. macOS only.
