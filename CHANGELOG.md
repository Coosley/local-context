# Changelog

## 0.2.0
- Status-word item tracking with percentages (`NOT STARTED` … `COMPLETED`), `IN REVIEW`, `FAILED`, `ABANDONED`.
- New files: `security.md`, `workflow.md`, `infrastructure.md`, `sessions/`, auto-generated `scan.md`.
- New commands: `doctor`, `wrap`, `brief`, `archive`, `scan`, `bootstrap`, `snapshot`, `history`, `restore`, `backup`, `team`, `version`, `uninstall`.
- Local version history of `.context/` (inner git repo), token budget checks, secret scan.
- Installer installs the latest release (or any pinned tag/branch/SHA); `ctx update [ref]`.
- Optional `team-context/` (committed) for shared team rules.
- Tests for PowerShell and POSIX sh, and CI.

## 0.1.0
- Initial release: `.context/` templates, `ctx init|status|upgrade`, one-line installers.
