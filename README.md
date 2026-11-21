# local-context

**A local, git-ignored "brain" for every workspace, readable by any AI agent in any harness.**

AI agents forget everything between sessions. `ctx` gives each project a `.context/` folder of plain Markdown that records where you came from, where you are, and where you're going. The agent reads it when it starts and updates it as it works, so the next session (or a different tool, or a different model) picks up exactly where the last one stopped.

- **Harness-agnostic:** plain Markdown plus one protocol file. Works with any LLM or tool that can read and write files. Nothing is hard-coded to a provider.
- **Local only:** hidden from git through `.git/info/exclude`. Nothing is committed and no `.gitignore` is touched.
- **Stateful:** items carry readable status words and percentages, so agents don't redo finished work.
- **Safe to lose:** the folder keeps its own version history, and `ctx backup` writes dated archives.
- **Checked:** `ctx doctor` validates items, catches secrets, stale work and context bloat.
- **Zero dependencies:** a PowerShell script and a POSIX shell script, both covered by tests and CI.

## Install (once per machine)

Windows (PowerShell):
```powershell
irm https://raw.githubusercontent.com/Coosley/local-context/main/install.ps1 | iex
```

macOS / Linux:
```sh
curl -fsSL https://raw.githubusercontent.com/Coosley/local-context/main/install.sh | sh
```

This downloads the latest release (or `main` if there is none) to `~/.local-context` and adds a `ctx` command to your PATH. Open a new terminal afterwards.

Piping a script to a shell is a trust decision. Read [install.ps1](install.ps1) or [install.sh](install.sh) first, and for maximum assurance pin a tag or commit: `CTX_REF=v0.2.0` (macOS/Linux) or `$env:CTX_REF='v0.2.0'` (PowerShell) before running the installer. See [SECURITY.md](SECURITY.md).

## Quick start

```sh
cd /path/to/your/workspace
ctx init
```

Then tell your agent, in any harness:

> Read .context/START_HERE.md and follow it. It is this workspace's local project memory.

For an existing project, run `ctx bootstrap`. It scans the repo (stack, tooling, CI, infrastructure) into `.context/scan.md` and prints a prompt that has the agent fill in `architecture.md`, `conventions.md`, `security.md` and the rest from facts, asking you at most five questions.

To make the instruction automatic, name the file your harness already reads (any name):

```powershell
ctx init . -Pointer AGENTS.md,CLAUDE.md       # Windows
```
```sh
ctx init . AGENTS.md CLAUDE.md                # macOS / Linux
```

That appends a two-line pointer to those files and excludes them from git if they aren't tracked.

## Commands

| Command | What it does |
|---|---|
| `ctx init [path]` | Create `.context/` from the templates, hide it from git, scan the repo, start snapshot history. Never overwrites your notes. |
| `ctx bootstrap` | Rescan and print the prompt that fills the context from the repo. |
| `ctx brief` | Print the always-load files plus progress. Made for session-start hooks. |
| `ctx status` | `STATE.md`, per-file progress (`3/7 completed (43%)`) and every open item. |
| `ctx doctor` | Check item syntax, duplicate IDs, percent rules, stale work, secrets, size and token budget. Exits 1 on errors. |
| `ctx wrap` | End of session: `doctor`, then a snapshot. |
| `ctx archive` | Move old log entries (keeps 15) and finished plans into `archive/`. |
| `ctx snapshot` / `history` / `restore <file> [rev]` | Local version history of `.context/`. |
| `ctx backup [path] [dest]` | Write a dated zip/tar archive (default `~/.local-context-backups/`). |
| `ctx team` | Create a committed `team-context/` for shared team rules. |
| `ctx scan` | Regenerate `scan.md`. |
| `ctx lock <file> [owner]` / `unlock` / `locks` | Short leases on shared files for parallel agents (stale after 10 minutes). |
| `ctx log "<text>"` | Append a dated entry to `log.md` safely. |
| `ctx agents [file]` | Export `team-context/` into a committable `AGENTS.md` block (idempotent). |
| `ctx hooks git` / `git-remove` / `claude` | Install the local post-commit snapshot hook, or print the Claude Code `SessionStart` hook. |
| `ctx upgrade` | Refresh the protocol and add any new template files to a workspace. |
| `ctx update [ref]` | Update the tool: latest release, or a tag/branch/commit. |
| `ctx uninstall -Yes` | Remove the tool (workspaces untouched). Use `--yes` on macOS/Linux. |

`path` defaults to the current folder.

## What's in `.context/`

```
.context/
  START_HERE.md     the protocol: the one file an agent must read
  STATE.md          dashboard: objective, focus, status, progress, next action
  goals.md          objectives, success criteria, non-goals
  plans/            one file per agreed plan, with tracked items
  todo.md           backlog not yet in a plan
  donts.md          things NOT to do, with reasons
  preferences.md    your preferences (style, tools, workflow)
  architecture.md   stack, modules, data flow, key files
  design.md         design tokens, components, UI rules
  conventions.md    code style, build/test/run commands
  deployment.md     environments, deploy steps, env var NAMES
  infrastructure.md providers (DNS, CDN/edge, hosting, DB), network config, runbook
  security.md       security posture and practices for this stack, agent security rules
  workflow.md       team and branching rules, PR process, active branches
  decisions.md      dated decisions and why
  gotchas.md        traps and non-obvious constraints
  log.md            append-only timeline, newest at the bottom
  sessions/         per-agent notes for parallel work
  scan.md           auto-generated repo facts (verify before relying)
  archive/          old log entries and finished plans (never loaded unless asked)
```

Files load in tiers to protect the context window: **Always** (`STATE.md`, `donts.md`, `preferences.md`, `security.md`, plus `team-context/` if present), **on demand** (everything else), **never unless asked** (`archive/`). The always tier has a ~3,000-token budget that `ctx doctor` checks.

## Tracking items

Every task, objective or practice is one readable line with a status word and a percentage, so you and the agent read progress the same way:

```
- T1 | COMPLETED 100% | Set up database | 2026-11-20 | migrations run, tests pass, commit abc123
- T2 | IN PROGRESS 60% | Build login form | 2026-11-21 | 3 of 5 subtasks done
- T3 | NOT STARTED 0%  | Password reset flow
- T4 | FAILED 30%      | Move to new ORM | 2026-11-19 | breaks raw queries
- T5 | ABANDONED 10%   | Dark mode v1 | 2026-11-18 | user dropped it
```

| Status | Meaning |
|---|---|
| `NOT STARTED` | Planned, 0%. |
| `IN PROGRESS` | Being worked on, 1–99% (from subtasks, or an honest estimate). |
| `IN REVIEW` | Agent thinks it's done; waiting for you to verify. |
| `BLOCKED` | Can't continue; the note says why. |
| `FAILED` | Tried and didn't work; the note says what was tried. |
| `ABANDONED` | You dropped it (only you decide this). |
| `COMPLETED` | Done and verified, 100%, with evidence. |

The agent prints progress in these same words (`Plan login-flow: 3/7 completed (43%)`) and says what changed after each update. You can steer in plain language: "T3 abandon", "T2 to 80%", "T2 completed". Agents never re-implement a `COMPLETED` item. If one looks broken, they check the code and add a new item.

## The loop

1. **Start:** the agent reads the always tier (or `ctx brief` does it for them).
2. **Plan:** agreed plans are saved to `plans/<date>-<slug>.md` before work begins.
3. **Work:** items move through `NOT STARTED`, `IN PROGRESS` and `COMPLETED` with a percentage. Decisions, gotchas, don'ts and preferences are written down as they come up.
4. **End:** the agent updates `STATE.md` (with a concrete next action), appends to `log.md`, and runs `ctx wrap`.

The full contract is in [templates/START_HERE.md](templates/START_HERE.md).

## Teams, branches and parallel agents

`.context/` is per clone and git-ignored, so teammates don't share it and `git checkout` doesn't switch it. So:

- Shared rules go in the repo. `ctx team` creates a committed `team-context/` (workflow, security, conventions) that agents read first and that wins over personal context.
- Plans carry a `Branch:` field, and agents note the current branch each session. They verify in the code before trusting a `COMPLETED` item from another branch.
- Parallel agents or worktrees write to `sessions/`, re-read a file before editing it, and append rather than rewrite. They take short leases with `ctx lock`/`unlock` around shared files and append with `ctx log`. `ctx doctor` flags duplicate IDs and stale locks. Locks are advisory: they help agents that cooperate, they don't stop one that ignores them.
- `ctx agents` exports your committed `team-context/` into an `AGENTS.md` block, so harnesses that auto-read `AGENTS.md` pick up the team rules. It never includes anything from your personal `.context/`.

## Automation (optional)

See [adapters/](adapters/README.md): `ctx hooks claude` prints a Claude Code `SessionStart` hook that injects `ctx brief` (checked against the hooks docs, not yet used in a live session), `ctx hooks git` installs a post-commit snapshot hook, and `ctx wrap` / `ctx backup` fit a scheduler. For other harnesses, point a session-start hook or rules file at `ctx brief`. The protocol works without any of them.

## How it relates to AGENTS.md, CLAUDE.md, Cursor rules and memory banks

Those files are great for *instructions* (how to work in this repo), and many tools read them automatically. `local-context` covers what they don't: private, per-developer *state* (plans, progress, decisions, preferences) with a status model, history, checks and a security/infra/workflow layer. They fit together: keep committed instructions in `AGENTS.md`/`CLAUDE.md`/`team-context/`, and point those files at `.context/` with `ctx init -Pointer`.

## Does it help?

Don't take our word for it. `sh evals/run.sh --agent '<your agent command>'` runs six scenarios with and without context against any agent CLI and checks the results mechanically ([evals/](evals/README.md)). The runner itself is tested with mock agents, but it has not yet been run against a real one, so there are no published results.

## FAQ

**Which tools does it work with?** Any agent or IDE that can read and write files in the workspace. The protocol is plain Markdown, and you point the agent at it with one sentence.

**Does anything force the agent to update the files?** No. It relies on the agent following `START_HERE.md`. `ctx doctor` and `ctx wrap` catch drift, and hooks (see adapters) can inject the context and run the checks automatically.

**Will it end up in my repo?** No. `.context/` goes into `.git/info/exclude`, which is local to your clone. If the folder isn't a git repo yet, run `ctx init` again after `git init`.

**What if I delete it?** `git clean -fdx` or a disk failure removes ignored files, including `.context/`. That's why there's `ctx backup` (copy somewhere safe) and the snapshot history inside the folder (`ctx history`, `ctx restore`). The history lives in the same folder, so only `ctx backup` protects you from deleting the folder itself.

**Can I keep it across machines?** `.context/` is machine-local by design. To sync it, put backups in a private repo or a synced drive yourself.

**Is it safe to store secrets in it?** No. The protocol tells agents to record env var names only, never values, and `ctx doctor` scans for secret-looking strings (best effort). Keep it that way.

**Uninstall?** `ctx uninstall -Yes` removes the tool and its PATH entry. Workspace `.context/` folders are yours and stay untouched.

## Repo layout

```
install.ps1 / install.sh    one-line installers (latest release or pinned ref)
ctx.ps1 / ctx.sh / ctx.cmd  the ctx command (Windows / POSIX / cmd shim)
templates/                  files copied into each workspace's .context/
team-templates/             starter for the committed team-context/
adapters/  evals/  tests/   hooks and automation notes, eval kit, test suites
VERSION  CHANGELOG.md       versioning
```

Run the tests with `powershell -File tests/run.ps1` or `sh tests/run.sh`. CI runs both on Windows, Linux and macOS.

## Forking

If you fork this, point the installers at your copy: replace `Coosley/local-context` in this README, `install.ps1` and `install.sh`, or set `CTX_REPO=owner/name` when installing.

## License

[MIT](LICENSE)
