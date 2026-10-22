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

Ticks can list unarchived Spaces and Start/Pause/Resume/Stop a timer. Space creation, editing,
archiving, manual time, voice memos and Auto Tick configuration stay in Tick.

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

## CI reliability and pre-push validation

- GitHub uses Xcode 26.6 on macOS arm64. Select that compiler through `DEVELOPER_DIR`, then run `bash scripts/ci.sh all` for the same clean build and complete unit/UI suite locally. Toolchain mismatches fail explicitly; report checks with another compiler separately.
- Keep the build, unit-test, and UI-test phases and all existing assertions. Before publishing CI, harness, or shared test-fixture changes, run the full relevant suite; focused/unit-only passes are partial evidence.
- Use explicit calendars/timezones for date fixtures, deterministic verified text replacement and readiness conditions for UI, and isolated cloud/Keychain fixtures where those services are not being tested. Repair a failing assumption across related tests rather than retrying or disabling it.
- Classify zero-step payment/spending-limit failures as unavailable execution evidence, separately from compilation, assertions, and deployment. Inspect annotations before editing code for an account block.
- Documentation-only pushes skip expensive CI; pull-request checks remain present for required statuses. Superseded same-ref runs are cancelled. Change pinned compiler/runtime versions deliberately and validate the complete suite.
