# scripts/

Build, release, and test tooling for sshCM.

| File | Purpose |
|---|---|
| `build-release.sh` | Build, sign, notarize, and staple a release; produces `dist/sshCM.app` + `dist/sshCM.zip`. See the "Release process" section in [`AGENTS.md`](../AGENTS.md). |
| `test-updater-e2e.sh` | Drive the auto-updater end-to-end against a **local** server — no GitHub publish. See below. |
| `ExportOptions.plist` | `xcodebuild -exportArchive` options template (team id substituted by `build-release.sh`). |

## Updater end-to-end test (`test-updater-e2e.sh`)

Serves a crafted `v9.9.9` release + `sshCM.zip` asset from a local `python3 -m http.server`,
points the app at it via the `SSHCM_RELEASES_API` env override, and launches sshCM so you can
drive **Check for Updates…** through the real UI — exercising download → parse → verify →
install / unsigned-opt-in without pushing anything to GitHub.

```
scripts/test-updater-e2e.sh [signed|adhoc] [/path/to/Source.app]
```

Prerequisites:
- A built `sshCM.app` (defaults to `.build/DerivedData/Build/Products/Debug/sshCM.app`). The
  loopback ATS exception (`NSAllowsLocalNetworking`) it needs is committed in `sshCM/Info.plist`,
  so a normal debug build is enough.
- `python3` on `PATH`.

### Mode `adhoc` — verify the unsigned opt-in prompt (works with the debug build)

```bash
scripts/test-updater-e2e.sh adhoc
```

1. Stages the app, re-signs it **ad-hoc**, zips it, starts the server, launches sshCM.
2. In the app: **menu → Check for Updates…** (or Settings → Updates → Check Now).
3. Expected: it downloads, signature pinning **rejects** it, and the
   **"Signature verification failed — Install Anyway"** sheet appears.
4. Click **Cancel** (don't install an ad-hoc build over your app). This covers the
   download/parse path, the `.confirmUnsigned` flow, and concurrent pipe draining.
5. **Ctrl-C** in the terminal to stop the server.

### Mode `signed` — verify the happy-path install (needs a Developer-ID build)

The debug build isn't Developer-ID-signed, so use a properly signed bundle:

```bash
# produce dist/sshCM.app (Developer ID signed) — needs the signing env vars from AGENTS.md
scripts/build-release.sh
scripts/test-updater-e2e.sh signed dist/sshCM.app
```

1. Launch → **Check for Updates…**
2. Expected: it downloads, verification **passes** (pinned to team `2RZL73M634`), it installs
   and **relaunches** — exercising the atomic swap/rollback installer script. The app it
   replaces is the `dist/sshCM.app` the script launched.

### Notes

- Default port is `8787`; override with `SSHCM_E2E_PORT=9000 scripts/test-updater-e2e.sh …`.
- The script cleans up its temp fixture and stops the server on exit.
- To check just the signer pin without the app (any bundle):
  ```bash
  codesign --verify --deep --strict \
    -R='anchor apple generic and certificate leaf[subject.OU] = "2RZL73M634"' <some.app>
  ```
  Ad-hoc / unsigned / foreign-team bundles return non-zero; a real sshCM release returns 0.
- The updater's install/confirm **state machine** is also covered headlessly by
  `UpdateCheckerTests` (`swift test`); this harness is for the network + `codesign`/swap
  parts that can't be unit-tested.
