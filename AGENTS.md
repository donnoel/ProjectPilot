# AGENTS.md

This repo is an Apple-platform app codebase. You are an engineering agent (Codex) collaborating with the human. Your job is to make small, correct, testable changes with a clean build at every step.

## Hard requirements (do not violate)
- **No build warnings.** Treat warnings as errors in practice.
- **No large rewrites.** Prefer small, surgical diffs.
- **Apple-native only.** No third-party libraries unless explicitly requested.
- **SwiftUI + MVVM.** Keep UI declarative; isolate logic in view models/services.
- **Concurrency correctness.** Avoid broad `@MainActor` on data models / filesystem / networking types. Use actors/services for isolation.
- **File persistence must be safe.** Use atomic writes where appropriate.
- **Privacy-first.** Local-first by default. No unexpected network calls.
- **Preserve pipeline contracts.** Do not regress scaffold flow, retry behavior, or status visibility without explicitly calling it out.

## Workflow
1. Read existing code and architecture before editing.
2. Propose a minimal plan in 2–5 bullets.
3. Implement the smallest viable patch.
4. Ensure build passes with **zero warnings**.
5. If tests exist or are touched, run them. Add tests for non-trivial logic.
6. If behavior changed, update docs (`README.md` / `AGENTS.project.md`) in the same patch.

## Code style
- Keep types small and focused.
- Prefer `Foundation` + `OSLog`/structured status over ad-hoc prints.
- Use actors/services for mutable shared state that should not run on the main thread.
- Prefer `@MainActor` only for UI/view models that must touch SwiftUI state.
- Avoid global singletons (unless explicitly designed).
- Keep command execution wrappers deterministic and easy to retry.

## Deliverables for each change
- Mention which files were modified and why.
- Provide a short commit message suggestion.
- Mention any user-visible behavior changes explicitly.

## What not to do
- Don’t introduce new dependencies.
- Don’t “fix” code by disabling concurrency checks.
- Don’t add `@MainActor` broadly to silence warnings.
- Don’t change public behavior without stating it.
- Don’t hide command failures; surface actionable status and retry paths.

If something is ambiguous, default to the simplest solution that preserves correctness and forward progress.
