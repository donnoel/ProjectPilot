# AGENTS.project.md

# ProjectPilot (macOS) Project Guide for Agents

## Product intent
**ProjectPilot** is a macOS menu bar app that scaffolds known-good Xcode projects quickly and predictably.
Core values: **consistency, reliability, local-first defaults, calm UX**.

## Current product phase (updated)
We have a robust scaffold pipeline with quality-of-life UX:
1) Project creation supports local folder creation, starter SwiftUI files, assets, tests, and `.xcodeproj` generation from a template pbxproj.
2) Platform targeting supports iOS, macOS, tvOS, with platform-aware project settings.
3) Git bootstrapping initializes local git, commits initial content, and keeps local default branch as `main`.
4) GitHub automation supports optional repo creation via `gh`, public/private visibility, remote name `github`, remote default branch `main`, and push retry without restarting full scaffold.
5) Project location is user-selectable (not fixed to one directory), with persisted selection.
6) Presets are supported (built-in + custom) and can store platforms, template profile, and GitHub visibility defaults.
7) Template profiles are supported so users can scaffold from multiple golden starter variants.
8) Post-create checklist actions include open in Xcode, open in Codex, open CLI in the project folder, reveal in Finder, and open Safari to the GitHub project page.
9) Inline validation hints appear before Create for project name (including requiring at least one letter or number).
10) Creation progress is visible with a compact step timeline (Folder → Xcodeproj → Git → GitHub → Open).
11) Failure diagnostics include an expandable details log panel with copy-to-clipboard support.
12) The popover separates **Basic** vs **Advanced** sections and supports keyboard-first flows (Enter create, Cmd+R retry, Esc clear status).
13) After a successful create, project form inputs reset to blank so the next scaffold starts clean.
14) The popover includes a **Codex** balance tab that reads local Codex session rollout data and shows near-real-time 5-hour, weekly, and credit usage status.

Current focus should be reliability, warning-free builds, and predictable generation behavior (especially honoring preset/platform intent).

## Architecture snapshot (current)
- **SwiftUI MenuBarExtra** app surface with a compact popover.
- **MVVM**: `ProjectPilotViewModel` (`@MainActor`) orchestrates user inputs and pipeline state.
- **Pipeline orchestration** lives in the view model with explicit step states and status messaging.
- **Process runner** wraps shell execution for `git` and `gh`, capturing output for status/details.
- **Template writer** generates project files and writes a customized `.xcodeproj` from embedded pbxproj text.

## Concurrency rules (important)
We are using Swift 6-era concurrency checks. Do NOT silence them with broad isolation.
- UI-bound view state in `ProjectPilotViewModel` can remain `@MainActor`.
- File IO and process execution helpers should stay deterministic and avoid blocking UI.
- Any shared mutable non-UI state introduced later should use actor/service isolation.

## Scaffold behavior invariants (do not regress)
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
- Keep defaults simple (Basic mode) and avoid overwhelming first-time users.
- Advanced controls should remain discoverable but optional.
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
