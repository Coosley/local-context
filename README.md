# local_context

**A local, git-ignored "brain" for every workspace, readable by any AI agent in any harness.**

AI agents forget everything between sessions. `ctx` gives each project a `.context/` folder of plain Markdown that records where you came from, where you are, and where you're going. The agent reads it when it starts and updates it as it works, so the next session (or a different tool, or a different model) picks up exactly where the last one stopped.

- **Harness-agnostic:** plain Markdown plus one protocol file. Works with any LLM or tool that can read and write files. Nothing is hard-coded to a provider.
- **Local only:** hidden from git through `.git/info/exclude`. Nothing is committed and no `.gitignore` is touched.
- **Stateful:** checklists with dates and evidence, so agents don't redo finished work.
- **Zero dependencies:** a PowerShell script and a POSIX shell script.

## Install (once per machine)

Windows (PowerShell):
```powershell
irm https://raw.githubusercontent.com/Coosley/local-context/main/install.ps1 | iex
```

macOS / Linux:
```sh
curl -fsSL https://raw.githubusercontent.com/Coosley/local-context/main/install.sh | sh
```

This downloads the repo to `~/.local-context` and adds a `ctx` command to your PATH. Open a new terminal afterwards. Piping scripts to a shell is a trust decision, so read [install.ps1](install.ps1) or [install.sh](install.sh) first if you like: they download this repo and edit your user PATH, nothing else.

## Quick start

```sh
cd /path/to/your/workspace
ctx init
```

Then tell your agent, in any harness:

> Read .context/START_HERE.md and follow it. It is this workspace's local project memory.

On the first session the agent bootstraps: it inspects the project, asks you a few questions, and fills in the files. After that it keeps them current.

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
| `ctx init [path]` | Create `.context/` from the templates, hide it from git. Never overwrites your notes. |
| `ctx status [path]` | Print `STATE.md` and every open checklist item in the workspace. |
| `ctx upgrade [path]` | Refresh `START_HERE.md` (the protocol) in this workspace. |
| `ctx update` | Update the tool itself from GitHub. |

`path` defaults to the current folder.

## What's in `.context/`

```
.context/
  START_HERE.md    the protocol: the one file an agent must read
  STATE.md         dashboard: objective, current focus, status, next action
  goals.md         objectives, success criteria, non-goals
  plans/           one file per agreed plan, with checklists
  todo.md          backlog not yet in a plan
  donts.md         things NOT to do, with reasons
  preferences.md   your preferences (style, tools, workflow)
  architecture.md  stack, modules, data flow, key files
  design.md        design tokens, components, UI rules
  conventions.md   code style, build/test/run commands
  deployment.md    environments, deploy steps, env var NAMES
  decisions.md     dated decisions and why
  gotchas.md       traps and non-obvious constraints
  log.md           append-only timeline, newest at the bottom
```

Agents always read `STATE.md`, `donts.md` and `preferences.md`. They read the rest only when relevant, which keeps the context window small.

## Checklists

Used in `plans/` and `todo.md`:

```
- [ ]  pending
- [~]  in progress
- [x]  done     (2026-11-21, tests pass / commit abc123)
- [-]  dropped  (2026-11-21, reason)
- [!]  blocked  (2026-11-21, what blocks it)
```

Agents mark `[x]` as soon as an item is finished and verified, with a date and evidence. They never re-implement a `[x]` item. If one looks broken, they check the code and add a new item.

## The loop

1. **Start:** the agent reads `STATE.md` and the files relevant to the task.
2. **Plan:** agreed plans are saved to `plans/<date>-<slug>.md` before work begins.
3. **Work:** items go `[~]`, then `[x]`. Decisions, gotchas, don'ts and preferences are written down as they come up.
4. **End:** the agent updates `STATE.md` (including a concrete next action), appends to `log.md`, and prunes anything stale.

The full contract is in [templates/START_HERE.md](templates/START_HERE.md).

## FAQ

**Which tools does it work with?** Any agent or IDE that can read and write files in the workspace. The protocol is plain Markdown, and you point the agent at it with one sentence.

**Does anything force the agent to update the files?** No. It relies on the agent following `START_HERE.md`. If it drifts, remind it of the end-of-session routine. If your harness supports hooks, you can add one that runs `ctx status` or prints `STATE.md` at session start.

**Will it end up in my repo?** No. `.context/` goes into `.git/info/exclude`, which is local to your clone. If the folder isn't a git repo yet, run `ctx init` again after `git init`.

**Can I keep it across machines?** `.context/` is machine-local by design. To sync it, put the folder in a private repo or a synced drive yourself.

**Is it safe to store secrets in it?** No. The protocol tells agents to record env var names only, never values. Keep it that way.

**Uninstall?** Delete `~/.local-context` and remove it from your PATH (on macOS/Linux also delete the `~/.local/bin/ctx` symlink). Workspace `.context/` folders are yours and stay untouched.

## Layout of this repo

```
install.ps1 / install.sh   one-line installers
ctx.ps1 / ctx.sh / ctx.cmd the ctx command (Windows / POSIX / cmd shim)
templates/                 files copied into each workspace's .context/
```

## Forking

If you fork this, point the installers at your copy: replace `Coosley/local-context` in this README, `install.ps1` and `install.sh`, or set `CTX_REPO=owner/name` when installing.

## License

[MIT](LICENSE)
