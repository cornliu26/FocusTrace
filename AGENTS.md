# FocusTrace repository instructions

## Product doctrine

- Read `Docs/PRODUCT_DOCTRINE.md` before changing product behavior, navigation, copy, analysis, reminders, or data collection.
- Every product change must identify one primary attention problem: seeing fragmented work, preserving interrupted context, or improving attention through evidence. A visible feature is not a valid goal by itself.
- Before implementation, state the observable user outcome, explicit non-goals and privacy boundary, and the complete loop from trigger through action, feedback, recovery, and exit.
- Do not add a new control, reminder, score, or workflow state when the same outcome can be completed through an existing path.
- Keep requirements and workflows conceptually separate: a requirement is a deliverable that may need timing and ordering; a workflow is the durable context in which work happens. Capturing one must not create or switch the other.
- FocusTrace is not a diagnosis tool, a general project manager, a notification blocker, or a content-monitoring product. Expanding one of these boundaries requires an explicit product decision before implementation.

## Iteration discipline

- Prefer the smallest complete vertical slice that improves a user outcome; do not land disconnected UI, storage, or analysis fragments.
- Treat shipped behavior, data compatibility, performance budgets, and deployment behavior as contracts. Consult `Docs/QUALITY_GATES.md` before implementation.
- Every behavior change needs a focused unit or integration test and, when it touches a shipped path, an explicit regression test. Performance-sensitive paths need a stable workload and budget.
- Add the new or changed capability to the quality baseline in `Docs/QUALITY_GATES.md`. Do not weaken an existing assertion or performance budget merely to make a change pass.
- Use `Docs/decisions/TEMPLATE.md` for a material product change. Record the problem, boundary, loop, evidence, and rollback condition before writing the feature.
- Keep changes small enough that a failed outcome can be reverted without rolling back unrelated improvements.

## Verification and deployment

- Run `./Scripts/test.sh` before committing behavioral or packaging changes.
- Use `./Scripts/build-app.sh` when only a distributable bundle is needed.
- Use `./Scripts/deploy-mac.sh` for local installation. Do not manually copy or launch the bundle from `dist/` as the normal deployment path.
- The Finder entry point is `Deploy-FocusTrace.command`; keep it as a thin wrapper around `Scripts/deploy-mac.sh`.
- A deployment must preserve the user's application data and preferences. Only replace the exact `FocusTrace.app` bundle in the selected installation directory.
- Keep the staged install, signature verification, graceful restart, and rollback behavior working when changing deployment scripts.
- Preserve published GitHub releases and tags. Do not delete historical releases unless the user explicitly requests a specific deletion.

## Privacy boundary

- Never commit generated reports, local application data, or files from `~/Library/Application Support/FocusTrace`.
- Do not inspect or expose raw activity logs for report/review requests.
- For a daily aggregate review, run `./Scripts/generate-daily-report.sh` and read only `.focustrace/reports/latest.json` and `.focustrace/reports/latest.md`.
- Both report artifacts must remain aggregate-only: no raw activity rows, Bundle IDs, event IDs, window titles, URLs, input content, or task parking recovery text.
- Reporting and deployment must not automatically alter training plans, allowed applications, notification settings, or other user preferences.

## UX invariants

- Keep the first-run mandatory path to one meaningful input: the current workflow name.
- Use “工作流” consistently in user-facing copy; “task” remains an internal model name only.
- The menu bar and main window must expose one shared primary next action through `FlowGuidanceEngine`.
- Keep schedule tuning, expected outcomes, allowed applications, plan history, exports, and deletion controls out of the primary daily path.
- In Space workflow mode, switching desktops is the workflow switch. Do not ask the user to select a destination workflow when parking work.
- Treat shipped interaction forms as compatibility contracts. In particular, keep date selection as a graphical calendar popover, keep the menu-bar panel compact, and update explicit UX regression tests before intentionally changing an established interaction.
- Capturing a requirement must never switch or bind a workflow. Requirements enter the inbox first; only the explicit “开始处理” action may activate or bind their assigned workflow.
- Keep timeline colors on the curated verdant palette and keep expensive timeline presentation work cached at minute/data-change granularity rather than recomputing on every focus-clock tick.
