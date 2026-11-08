# AGENTS.project.md

# ProjectPilot (macOS) Project Guide for Agents

## Product intent
**ProjectPilot** is a macOS menu bar companion for Ticks, Codex usage, GitHub repositories, development backups, and focused system health warnings.
Core values: **consistency, reliability, local-first defaults, calm UX**.

## Current product phase

Don confirmed on October 18, 2026 that the current ProjectPilot work is complete with no outstanding closeout tasks, including prior acceptance and delete-confirmation follow-ups. This is owner confirmation, not a new test run, independently observed device acceptance, or a release claim. Treat new requests or reported regressions as follow-up work.

The active tabs are **Ticks, Codex, GitHub, Backup, System Health**. The selected tab is persisted;
Ticks is the initial default. Basic/Advanced, Create, pipeline progress and scaffold
keyboard shortcuts are removed from the UI. The legacy scaffold engine remains
internally and its invariants below still apply when touching that code.

Ticks can list unarchived Spaces, Start/Pause/Resume/Stop a timer, and edit the displayed
running Tick's description and notes. Space creation, editing, archiving, manual time,
voice memos and Auto Tick configuration stay in Tick.

## Architecture snapshot

- SwiftUI `MenuBarExtra` hosts `ProjectPilotPopover`.
- `ProjectPilotViewModel` owns existing Codex/GitHub/backup and legacy scaffold logic.
- `TicksViewModel` owns the Ticks UI; `TicksStore` is an actor for the Mac cache,
  pending uploads, account binding and CloudKit synchronization.
- `../Tick/Package.swift` provides the first-party `TickCore` package. The mobile
  app/widget compile the same sources directly. Do not fork its schema or merge rules.
- The Mac cache is separate from Tick's App Group storage. Read
  `docs/TICKS_INTEGRATION.md` before changing timer, cloud or delivery behavior.
- The app uses its original MenuBarExtra scene; the temporary UI-test window was
  removed. Automated Ticks coverage is in the unit tests and shared TickCore tests.
- Live cloud access requires the ProjectPilot provisioning profile; local fixture
  tests do not prove physical-device sync. The previous Tick widget propagation
  checkpoint is historical; the current follow-up is closed by Don's October 18 confirmation,
  without claiming new independent device verification.

## Codex backup contract

- `CodexCloudBackup` captures selected Codex data into AES-256 encrypted disk images.
  Read `docs/CODEX_BACKUP.md` before changing its scope, encryption, retention, or
  restore behavior. The existing readable skills mirror remains separate.
- Preserve password recovery acknowledgment and device-only Keychain storage.
  Never put passwords into process arguments, logs, archives, UserDefaults, Git,
  or the cloud folder. No plaintext fallback on encryption failure.
- Use consistent SQLite snapshots and integrity checks, serialize backup writers,
  verify ciphertext before rotation, and preserve the last good archive on failure.
- Label the local iCloud copy separately from confirmed server upload. Fixture
  restore tests do not establish a successful rebuild of the user's real Mac.

## Concurrency rules (important)
We are using Swift 6-era concurrency checks. Do NOT silence them with broad isolation.
- UI-bound view state in `ProjectPilotViewModel` can remain `@MainActor`.
- File IO and process execution helpers should stay deterministic and avoid blocking UI.
- Any shared mutable non-UI state introduced later should use actor/service isolation.

## Legacy scaffold behavior invariants (do not regress when touching that code)
When user creates a project:
1) Validate project name first.
2) Create folder and project files.
3) Generate `.xcodeproj` and apply selected platform settings.
4) Initialize git and commit initial content.
5) Optionally run GitHub creation/push when enabled.
6) Expose actionable retry path for recoverable GitHub failures.
7) Keep progress timeline and details panel in sync with pipeline outcomes.

Additional expectations:
- Preset selection must be honored for effective platform destinations/settings.
- Local-only scaffolding must skip GitHub cleanly.
- Error messaging should be plain language and actionable.

## UX rules
- Keep the Ticks tab focused on selecting a Space and starting/pausing/resuming/stopping time.
- Never expose Space management or scaffold actions in the Ticks flow.
- Preserve keyboard-first affordances and clear status feedback.
- Keep the popover responsive and foreground-friendly for folder selection and actions.

## Coding conventions
- Keep diffs small, explicit, and reversible.
- Prefer clear helper methods over duplicated inline command logic.
- Keep string transformations for pbxproj edits narrowly scoped and safe.
- Use strong validation and sanitization for project/repo names.

## Build/run notes
- Target: macOS app (SwiftUI/MenuBarExtra).
- Maintain **clean build**: no warnings.
- If new files are added, ensure they are included in the correct target when required.

## Current closeout

- No outstanding work as confirmed by Don on October 18, 2026.
- The legacy scaffold engine is retained internally, not the current product purpose or an active work queue.
- Additional diagnostics, coverage, or feature work requires a new request.

## Output expectations per patch
Provide:
- Summary of change
- Files modified
- Any migration considerations
- Commit message suggestion

## CI reliability and local validation

- For ordinary changes, start with the narrowest relevant build, unit test or UI check. Expand for shared behavior, persistence, startup or release risk. Documentation and local tool-selection helper changes need scoped structural/contract checks; they do not require an application rebuild solely to repeat CI.
- Use `bash scripts/local-check.sh <command> [args...]` for local checks. It selects the fixed local Xcode 27.0 (27A266a), rejects conflicting compiler selections, and never installs or switches global tools. Use the shared Apple target helper for concrete destinations. Hosted CI baselines remain separate.
- GitHub keeps Xcode 26.6 on macOS arm64. Its strict `ci.sh` may reject the local Xcode 27 compiler; this is a documented baseline difference. Do not switch local compilers or create a fresh simulator automatically. Historical matched-CI reproduction must be explicitly requested and scoped separately; keep existing hosted checks intact.
- Run the complete affected suites when changing build/test workflow behavior, test harnesses or shared fixtures, or when reproducing a hosted failure. Full local CI is not a blanket prerequisite for every edit. Keep GitHub CI enabled and all existing suites/assertions; a focused pass is not a full-suite pass.
- Check installed tools and equivalent capabilities before proposing a download. Do not install or switch global tools merely to obtain exact CI parity for an unrelated change. Report local compiler/runtime/browser/OS differences and checks not run; only observed GitHub results establish hosted CI success.
- Keep the build, unit-test, and UI-test phases and all existing assertions. Build/test workflow, harness and shared-fixture changes require complete affected-suite evidence.
- Use explicit calendars/timezones for date fixtures, deterministic verified text replacement and readiness conditions for UI, and isolated cloud/Keychain fixtures where those services are not being tested. Repair a failing assumption across related tests rather than retrying or disabling it.
- Classify zero-step payment/spending-limit failures as unavailable execution evidence, separately from compilation, assertions, and deployment. Inspect annotations before editing code for an account block.
- Documentation-only pushes skip expensive CI; optional pull-request checks remain present. Superseded same-ref runs are cancelled. Change pinned compiler/runtime versions deliberately and validate the complete suite.
