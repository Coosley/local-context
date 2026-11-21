# START HERE — Local Context Protocol

This folder (`.context/`) is the **local, git-ignored brain** of this workspace. It is written for **any AI agent in any harness**. It is plain Markdown: read it with whatever file access you have, edit it the same way. Nothing here is specific to a provider or tool.

You have no memory between sessions. **This folder is your memory.** Treat it as the source of truth for *intent* (goals, plans, decisions, preferences). Treat the code as the source of truth for *what exists*. If they disagree, verify in the code, then fix the context.

---

## 1. At the start of every session

1. Read `STATE.md` (always). It tells you the objective, current focus, and next action.
2. Read `donts.md` and `preferences.md` (short, always).
3. Read the other files **only when relevant** to the task:

| File | Holds |
|---|---|
| `STATE.md` | Dashboard: objective, focus, status, next action. Keep < 40 lines. |
| `goals.md` | Objectives, success criteria, non-goals. |
| `plans/` | One file per plan. Checklists with status and dates. |
| `todo.md` | Backlog not yet part of a plan. |
| `donts.md` | Things NOT to do, and why. |
| `preferences.md` | The user's preferences (style, tone, tools, workflow). |
| `architecture.md` | Modules, data flow, key files, stack. |
| `design.md` | Design system: tokens (color, type, spacing), components, UI rules. |
| `conventions.md` | Code style, patterns, build/test/run commands. |
| `deployment.md` | Environments, deploy steps, hosting, env var NAMES (never values). |
| `decisions.md` | Dated decisions and the reasons behind them. |
| `gotchas.md` | Traps, bugs hit, non-obvious constraints. |
| `log.md` | Append-only timeline of what happened, newest at bottom. |

4. If the files are still templates (placeholders like `<...>`), **bootstrap**: inspect the workspace and ask the user short questions, then fill them in. Do not invent facts.

## 2. Checklist semantics (used in `plans/`, `todo.md`)

```
- [ ]  pending
- [~]  in progress (at most one or two at a time)
- [x]  done        -> append: (YYYY-MM-DD, evidence)   e.g. (2026-11-21, commit abc123 / tests pass)
- [-]  dropped     -> append: (YYYY-MM-DD, reason)
- [!]  blocked     -> append: (YYYY-MM-DD, what blocks it)
```

**Never re-implement an item marked `[x]`.** If you doubt it, verify in the code first; if it is actually broken, add a new item rather than silently un-checking.

## 3. While working

- When the user and you agree a plan, **write it to `plans/<yyyy-mm-dd>-<slug>.md` before starting** (use `plans/_template.md`). Plans are point-in-time records: keep them, mark status, don't delete.
- Mark `[~]` when you start an item and `[x]` **immediately** when it is finished and verified, not at the end of the session.
- New work that appears mid-task goes in `todo.md` (or the plan), not into your head.
- When you make a non-obvious choice, add it to `decisions.md`. When you hit a trap, add it to `gotchas.md`. When the user says "don't do X" or "I prefer Y", add it to `donts.md` / `preferences.md` right away.
- When you change architecture, design tokens, conventions, or deployment, update the matching file in the same task.

## 4. At the end of every session or task

1. Tick off finished items; mark unfinished ones honestly.
2. Update `STATE.md`: current focus, status, **next action** (concrete enough for a cold start).
3. Append a short entry to `log.md`: date, what changed, what's next, open questions.
4. Prune anything now false. Stale context is worse than none.

## 5. Writing rules

- Short, factual, scannable. Bullets over prose. Dates in `YYYY-MM-DD`.
- Record *why*, not just *what*. Don't paste code or file listings the repo already shows; point to paths instead.
- One fact lives in one file. Link, don't duplicate.
- **Never store secrets** (keys, tokens, passwords, personal data). Names of env vars only.
- Don't rewrite history in `log.md` or `decisions.md`; supersede with a new dated entry.
- Keep this folder local. Do not commit it, push it, or paste it into external services.

## 6. If you are the user's first agent in a new workspace

Run the bootstrap in step 1.4, then tell the user what you filled in and what is still unknown.
