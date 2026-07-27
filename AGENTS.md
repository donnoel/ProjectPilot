This is an Apple-platform app repository. Work from concrete repository evidence and make small, correct, testable changes.

## Hard requirements

- **No build warnings.** Treat warnings as errors.
- **No large rewrites.** Prefer small, surgical diffs.
- **Apple-native only.** No third-party libraries unless explicitly requested.
- **SwiftUI + MVVM.** Keep UI declarative; isolate logic in view models and services.
- **Concurrency correctness.** Do not silence warnings with broad `@MainActor`. Use actors/services for non-UI mutable state.
- **Safe persistence.** Use atomic writes where appropriate.
- **Privacy-first.** No unexpected network calls or data collection.
- **Preserve behavior.** Do not regress user-visible flows without calling it out.
- **Accessibility matters.** Treat accessibility as part of the feature, not polish.

## Authorization

- For an audit, review, explanation, or diagnosis, inspect and report; do not edit unless the request also asks for a change.
- For a fix, feature, build, or refactor, make the smallest in-scope local change and run relevant non-destructive validation.
- Ask before destructive actions, external writes, purchases, new dependencies, or a material expansion of scope. Ask about other ambiguity only when it could change product behavior or the safe implementation.

## Workflow

1. Read the applicable `AGENTS.project.md` and only the files needed for the task.
2. Use targeted searches and current build, test, log, or runtime evidence before forming conclusions.
3. Make a brief plan for non-trivial work.
4. Implement the smallest viable patch without unrelated cleanup.
5. Run the narrowest validation that proves the changed contract.
6. Report the outcome, files changed, validation performed, and anything skipped or unverified.

## Code guidance

- Keep types, state ownership, and side-effect boundaries explicit and focused.
- Prefer derived state over duplicated state and structured logging over ad-hoc prints.
- Add abstractions only when they reduce real coupling, duplication, or test friction.
- Avoid expensive work in SwiftUI render paths, unbounded caches, and unnecessary main-thread work.

## Accessibility baseline

For user-facing changes, check semantic controls, labels and values, reading and focus order, scalable text, contrast, hit targets, state communication, and relevant Reduce Motion or Reduce Transparency behavior. Do not claim accessibility support without concrete implementation evidence.

## Validation

Start with the touched target or focused test. Use broader tests only for shared architecture, persistence, startup, release behavior, or similarly broad changes. Documentation-only changes need diff and formatting checks, not an app build, unless project guidance says otherwise.
