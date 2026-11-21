# Adapters (optional)

The protocol works with no tooling: you point an agent at `.context/START_HERE.md` and it follows the rules. Adapters just make that automatic in harnesses that support it. They never replace the protocol, and nothing here is required.

Two commands are designed for automation:

| Command | Prints / does | Use it as |
|---|---|---|
| `ctx brief` | The Always tier plus progress, to stdout | a session-start hook, or text you paste |
| `ctx wrap` | Runs `doctor`, saves a snapshot, exits non-zero on errors | an end-of-session hook or a manual check |

## Any harness without hooks
- Put the one-line pointer in whatever instruction file it reads: `ctx init . -Pointer <file>` (Windows) or `ctx init . <file>` (macOS/Linux).
- Or paste the output of `ctx brief` as your first message.

## Harnesses with hooks (example only; check your harness's docs for the exact format)
A session-start hook that runs `ctx brief` and an end hook that runs `ctx wrap`. For example, in a harness that uses a JSON settings file with command hooks:

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "ctx brief" }] }]
  }
}
```

## Git hooks (any workflow)
Keep a local history automatically by snapshotting after each commit. In `.git/hooks/post-commit` (and make it executable):

```sh
#!/bin/sh
ctx snapshot . "after commit" >/dev/null 2>&1 || true
```

## Scheduled backup
Run `ctx backup` from your scheduler (Task Scheduler, cron) to write a dated archive to `~/.local-context-backups/`.
