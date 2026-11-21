# Changelog

## 0.1.1
- README documents the npm package (`npx @coosley/local-context init`, `npm install -g @coosley/local-context`).
- The npm publish workflow now skips publishing, instead of failing, when the `NPM_TOKEN` secret isn't set.

## 0.1.0 (first release)
- `.context/` templates for any agent in any harness: protocol (`START_HERE.md`), `STATE.md`, goals, plans, backlog, don'ts, preferences, architecture, design, conventions, deployment, infrastructure, security, workflow, decisions, gotchas, log, sessions.
- Status-word item tracking with percentages (`NOT STARTED`, `IN PROGRESS`, `IN REVIEW`, `BLOCKED`, `FAILED`, `ABANDONED`, `COMPLETED`).
- `ctx` commands: `init`, `status`, `brief`, `doctor`, `wrap`, `archive`, `scan`, `bootstrap`, `snapshot`, `history`, `restore`, `backup`, `team`, `agents`, `lock`/`unlock`/`locks`, `log`, `hooks`, `upgrade`, `update`, `uninstall`, `version`.
- Local version history of `.context/`, token-budget and secret checks, archive of old entries and finished plans.
- Optional committed `team-context/` for shared team rules, exportable to an `AGENTS.md` block.
- Git post-commit snapshot hook and a Claude Code `SessionStart` hook (checked against the docs, not yet used in a live session).
- One-line installers for Windows and macOS/Linux (latest release or any pinned tag, branch or commit), `ctx update`, `ctx uninstall`.
- Eval kit: six scenarios, an automated runner with `--prepare`/`--score` modes, mock agents for self-testing, and a first small smoke-test result.
- Tests for PowerShell and POSIX sh, and CI on Windows, Linux and macOS.
