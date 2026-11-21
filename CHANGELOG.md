# Changelog

## 0.3.0
- `ctx lock` / `unlock` / `locks`: short leases on shared files for parallel agents (stale after 10 minutes, `CTX_LOCK_TTL`). `doctor` reports stale locks.
- `ctx log "<text>"`: safe append to `log.md`.
- `ctx agents [file]`: export `team-context/` into a committable `AGENTS.md` block (idempotent; refuses unfilled templates).
- `ctx hooks git|git-remove|claude`: local post-commit snapshot hook; prints a Claude Code `SessionStart` hook checked against the hooks docs.
- Automated eval runner `evals/run.sh` with mock agents for self-testing the runner.
- Secret scan now covers every text file in `.context/`, not only Markdown.
- Snapshot history ignores `.locks/`.
- Tests cover all of the above.

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
