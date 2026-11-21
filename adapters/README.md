# Adapters (optional)

The protocol works with no tooling: you point an agent at `.context/START_HERE.md` and it follows the rules. Adapters just make that automatic in harnesses that support it. They never replace the protocol, and nothing here is required.

Two commands are designed for automation:

| Command | Prints / does | Use it as |
|---|---|---|
| `ctx brief` | The Always tier plus progress, to stdout | a session-start hook, or text you paste |
| `ctx wrap` | Runs `doctor`, saves a snapshot, exits non-zero on errors | an end-of-session check you or a hook run |

## Any harness without hooks
- Put the one-line pointer in whatever instruction file it reads: `ctx init . -Pointer <file>` (Windows) or `ctx init . <file>` (macOS/Linux).
- Or paste the output of `ctx brief` as your first message.

## Claude Code
Print the config with `ctx hooks claude`. In short, merge this into `.claude/settings.local.json` (this project, not committed) or `~/.claude/settings.json` (all projects):

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "ctx brief" } ] }
    ]
  }
}
```

What the hooks documentation (code.claude.com/docs/en/hooks) says, which this adapter relies on:
- Hooks nest as event → matcher group → handlers. A `SessionStart` matcher is optional (`startup`, `resume`, `clear`, `compact`, `fork` narrow it).
- A `SessionStart` hook's plain-text stdout on exit 0 is added to Claude's context. That is what `ctx brief` prints.
- There is deliberately no `Stop` hook: plain stdout from `Stop` does not reach the model, and blocking a stop to force an update risks loops. Run `ctx wrap` yourself, or use the git hook below.

Status: the settings structure was checked against the docs, but I have not run it inside a live Claude Code session. Treat it as verified-by-docs, not verified-by-use.

## Git hook (any workflow, tested)
`ctx hooks git` installs a local `post-commit` hook that saves a `.context` snapshot after every commit (it appends to an existing hook and `ctx hooks git-remove` takes it out). It is local to your clone and never committed.

## Other harnesses
I don't ship configs for harnesses I haven't verified. If yours supports a session-start command hook or a rules file, point it at `ctx brief` (or at the one-line pointer above). The contract is just: stdout of `ctx brief` goes into the model's context.

## Parallel agents
Agents sharing a workspace should use `ctx lock <file> <name>` / `ctx unlock <file> <name>` around edits to shared files and `ctx log "<text>"` to append to the log. Locks are leases (stale after 10 minutes, set `CTX_LOCK_TTL` seconds to change), and `ctx locks` lists them.

## Scheduled backup
Run `ctx backup` from your scheduler (Task Scheduler, cron) to write a dated archive to `~/.local-context-backups/`.
