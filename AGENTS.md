# FocusTrace repository instructions

## Verification and deployment

- Run `./Scripts/test.sh` before committing behavioral or packaging changes.
- Use `./Scripts/build-app.sh` when only a distributable bundle is needed.
- Use `./Scripts/deploy-mac.sh` for local installation. Do not manually copy or launch the bundle from `dist/` as the normal deployment path.
- The Finder entry point is `Deploy-FocusTrace.command`; keep it as a thin wrapper around `Scripts/deploy-mac.sh`.
- A deployment must preserve the user's application data and preferences. Only replace the exact `FocusTrace.app` bundle in the selected installation directory.
- Keep the staged install, signature verification, graceful restart, and rollback behavior working when changing deployment scripts.

## Privacy boundary

- Never commit generated reports, local application data, or files from `~/Library/Application Support/FocusTrace`.
- Do not inspect or expose raw activity logs for report/review requests.
- For a daily aggregate review, run `./Scripts/generate-daily-report.sh` and read only `.focustrace/reports/latest.md`.
- Reporting and deployment must not automatically alter training plans, allowed applications, notification settings, or other user preferences.
