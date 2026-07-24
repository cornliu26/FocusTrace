# FocusTrace repository instructions

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
