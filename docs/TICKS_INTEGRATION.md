# Ticks integration

ProjectPilot is a Mac client for the existing Ticks data. It lists unarchived
Spaces and starts/stops one timer. Create/edit/archive Spaces in the mobile app.
Codex, GitHub and Backup remain available. The scaffold engine and its tests are
retained internally; its Basic/Advanced tabs, Create button and shortcuts are gone.

## Shared implementation

Keep the `ProjectPilot` and `Tick` checkouts as siblings. `../Tick/Package.swift`
exports the first-party `TickCore` library. The iPhone app and widget compile
those exact sources directly, so their wire format, CloudKit transport and
conflict resolver cannot drift from this checkout's Mac client. No third-party
package or new server is required. Commit/review changes in both repositories
together when changing this integration.

`TicksViewModel` owns Mac UI state. `TicksStore` owns file access and cloud work
on an actor. `TickTimerMutation` supplies widget/Mac Start/Stop and the mobile
app's paused Stop date calculation. Cloud mutations preserve the full snapshot,
including session notes and Auto Tick rules that have no Mac editing controls.
Voice memo files remain outside this integration.

The Mac cache lives at
`~/Library/Application Support/dn.ProjectPilot/Ticks/<environment>/state.json`.
The snapshot and last server acknowledgment are written atomically together;
their difference is the durable pending upload. No App Group file is shared
between the Mac and mobile devices. A corrupt cache is preserved and blocks
writes. Switching Apple accounts also blocks writes and preserves the cache.
Reconnect the original account to resume; automatic account-data migration is
not implemented.

## Cloud setup and delivery

The signed Mac target must belong to team `H7LG8SK72M` and have access to the
existing `iCloud.dn.tick` container, CloudKit and push notifications. It uses the
same user's private database and `TickSnapshotV1` / `snapshot-v1` record as Tick.
ProjectPilot has its own notification subscription identifier. The Xcode project
contains the requested entitlements; Apple must also grant them in its profile.

Debug uses the Development CloudKit environment; Release uses Production, with
separate local caches. All participating builds must use the same environment
and Apple account. An empty development database is not evidence that production
Spaces are missing. First connection never creates an empty cloud record.

`./script/build_and_run.sh --build-only` builds using existing profiles.
The default command stops the running ProjectPilot, builds, then launches the
new artifact. It does not request provisioning updates or replace `/Applications`.
The Codex Run action uses this script. `--verify`, `--debug`, `--logs` and
`--telemetry` provide process and diagnostic options.

The user authorized provisioning on September 7, 2026. Xcode created the
`dn.ProjectPilot` Mac development profile, and the signed app connected to the
existing container. Physical cross-device action propagation remains a separate
check; signing and reading cloud data alone do not prove that round trip.

## Behavior and recovery

- Start/Stop refresh first when online. The action keeps the time the user clicked.
- Offline capture requires a previously loaded, account-bound cloud snapshot.
  Changes persist locally and retry; authentication/data errors block mutation.
- Stop targets the displayed session ID, never a replacement timer that arrived
  during refresh. Repeated Stop is harmless. Stopping a paused session excludes
  paused time.
- Existing Tick merge rules apply: Stop is terminal, deletions stay deleted, and
  concurrent starts retain their records but converge to one active timer.
- Refresh runs on opening Ticks, wake, cloud notification and a periodic retry
  (30 seconds while visible or with pending uploads; five minutes otherwise).
- “Last checked” refers to this Mac's cloud acknowledgment, not an acknowledgment
  from the iPhone/iPad. A receiving widget can update later under WidgetKit's
  background scheduling. The existing Tick checkpoint `4e84aa9` reports unresolved
  physical cross-device widget Stop propagation; this integration does not claim
  that historical issue is fixed by unit tests.

## Validation

Use warnings as errors and `SWIFT_SUPPRESS_WARNINGS=NO` for Xcode builds. Xcode's
default package warning suppression otherwise conflicts with warnings-as-errors.
AppIntents is linked for Xcode's metadata extraction pass, including test bundles.

Run shared tests with `swift test --package-path ../Tick -Xswiftc -warnings-as-errors`.
ProjectPilot unit tests cover three simulated clients, retry after relaunch,
optimistic conflicts, account isolation, corrupt/missing records and stale Stop.
The temporary debug UI-test window was removed to restore the original menu-bar
scene. Ticks Start/Stop and tab restoration require manual UI verification;
the original UI-test template does not cover those flows.

Before delivery, verify a signed Mac start → iPhone stop, iPad start → Mac stop,
relaunch/offline recovery, and receiving widgets on the physical devices. Check
VoiceOver reading order and appearance with the user's accessibility settings.
No live timer or cloud records are created by the automated tests.

## Implementation verification — 2026-09-07

- 40 ProjectPilot unit tests passed, including the Mac cache/sync and UI-state tests.
- 100 Tick unit tests passed on the iOS simulator, including paused widget Stop.
- Seven shared TickCore tests passed. These use fixtures, not live cloud data.
- Mac and iOS builds completed without build warnings using warnings as errors.
  The Mac fixture was signed with the existing Apple Development identity and
  omitted cloud entitlements only for isolated UI validation.
- The native preview's four tabs and Space selector were inspected. The UI test
  runner was stopped by macOS Gatekeeper before executing any UI tests, even
  after signing with the existing development identity. No security settings
  were changed. Full UI Start/Stop and VoiceOver checks remain pending.
- The normal signed Mac build is blocked by the missing `dn.ProjectPilot` Mac
  development provisioning profile. Live iCloud access and physical three-device
  propagation are not yet verified. No installed mobile build or timer history
  was changed by this implementation.

### Live connection completed

On September 7, following explicit user approval, Xcode created the Mac development
profile and built ProjectPilot without warnings. The signed app loaded 19 Spaces
and 307 sessions from the existing Development CloudKit record, wrote its local
acknowledgment, and reported no pending upload. Automatic refresh now starts with
the app so queued changes retry even before the menu is opened.

The signed build was installed in `/Applications/ProjectPilot.app`; the previous
app was retained under `~/Library/Application Support/ProjectPilot/Rollback/`.
No live timer was started/stopped for this connection check. A real Start/Stop
round trip with the physical iPhone/iPad and widget refresh remains unverified.
