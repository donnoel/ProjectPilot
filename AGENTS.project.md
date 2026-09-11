# AGENTS.project.md

# ProjectPilot (macOS) Project Guide for Agents

## Product intent
**ProjectPilot** is a macOS menu bar companion for Ticks, Codex usage, GitHub repositories, development backups, and focused system health warnings.
Core values: **consistency, reliability, local-first defaults, calm UX**.

## Current product phase

The active tabs are **Ticks, Codex, GitHub, Backup, System Health**. The selected tab is persisted;
Ticks is the initial default. Basic/Advanced, Create, pipeline progress and scaffold
keyboard shortcuts are removed from the UI. The legacy scaffold engine remains
internally and its invariants below still apply when touching that code.

Ticks can list unarchived Spaces and Start/Stop a timer. Space creation, editing,
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
  checkpoint remains unverified until tested on devices.

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
- Keep the Ticks tab focused on selecting a Space and starting/stopping time.
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

## Near-term priorities
- Expand automated tests around preset application and generated destination correctness.
- Improve pbxproj update robustness for future template variations.
- Continue polishing failure diagnostics and recovery UX.

## Output expectations per patch
Provide:
- Summary of change
- Files modified
- Any migration considerations
- Commit message suggestion
