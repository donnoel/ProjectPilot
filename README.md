# ProjectPilot

ProjectPilot is a native macOS menu bar companion for Ticks, Codex usage,
GitHub repositories, development backups, and focused system health warnings.

## Tabs

- **Ticks** — choose an existing Space, see the active or paused Tick, and
  Start/Stop recording. Create and manage Spaces in Ticks on iPhone or iPad.
- **Codex** — inspect usage limits and credits from local Codex session data.
- **GitHub** — browse repositories with separate local Git sync and current-default-branch CI status.
- **Backup** — check and update the development-folder mirror in iCloud Drive.
- **System Health** — see only actionable disk, developer-storage, Docker,
  backup, and required-tool warnings, or a calm All clear state.

Ticks is the initial tab. Your selected tab is remembered across launches.
Basic and Advanced, their Create button, and scaffold shortcuts have been
removed from the interface. The underlying scaffold engine and its tests remain
in the repository.

## Ticks setup

Keep the `ProjectPilot` and `Tick` checkouts alongside one another. ProjectPilot
imports `../Tick/Package.swift` as the first-party `TickCore` library; both apps
use the same data format, CloudKit transport, and conflict rules.

Live sync requires a signed ProjectPilot build authorized for `iCloud.dn.tick`,
with the same iCloud account and CloudKit environment as the mobile builds.
Debug uses Development; Release uses Production. Spaces in one environment do
not appear in the other. The Mac development provisioning profile was created and the live connection
verified on September 7, 2026.

The Mac keeps an atomic local cache and retries pending changes. It shows when
an action is saved locally and waiting for iCloud. “Last checked” confirms the
Mac's server check; it does not claim that a receiving phone or widget has
already refreshed. Tick's existing physical widget Stop-propagation issue remains
an explicit validation checkpoint.

See [Ticks integration](docs/TICKS_INTEGRATION.md) for signing, storage, account
isolation, conflict behavior, tests, and the three-device delivery checks.

## Build and run

Open `ProjectPilot.xcodeproj` in Xcode, or use:

```sh
./script/build_and_run.sh --build-only
./script/build_and_run.sh --verify
```

The script uses existing signing profiles and treats warnings as errors.
The default Run action stops the current ProjectPilot, builds, and launches the
new build. It does not replace the installed app or change Apple provisioning.
GitHub features require the existing `gh` CLI to be authenticated.

## Development backup

ProjectPilot mirrors `~/Development` into iCloud Drive's `Development` folder,
including Git history and excluding generated build/dependency folders. The local
folder is the source of truth; files removed locally are removed from the mirror.

Automatic backups use filesystem notifications. They wait for 60 seconds of quiet,
start no more than once every five minutes, and batch continuous edits for up to
15 minutes. An hourly reconciliation catches missed events; failed attempts wait
15 minutes before retrying. Opening Backup does not force a copy. **Back up now**
starts one immediately. Changes arriving during a copy remain pending.

“Backup updated” means the local iCloud Drive copy completed, not that Apple's
cloud upload has finished. Existing backup settings and data are unchanged.
