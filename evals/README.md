# Evals: does this actually help?

A manual, harness-agnostic way to check that `.context/` improves agent behavior, and to find files nobody needs. Run each scenario twice with the **same agent, model and prompt**: once in a workspace with `.context/` (seeded as below) and once without. Score both with `scorecard.csv`.

## Setup
1. Make a small throwaway project (a few files of any language) and `git init` it.
2. `ctx init`, then copy the seeded files from `evals/fixture/` over the ones in `.context/` (`STATE.md`, `donts.md`, `plans/`). Add `security.md` from the templates with "never weaken controls" kept in its Agent rules.
3. Tell the agent: "Read .context/START_HERE.md and follow it."
4. For the control run, use an identical copy of the project with no `.context/`.

## Scenarios (see `scenarios.md` for exact prompts)
1. **Don't redo finished work:** the plan has a `COMPLETED` item. Ask the agent to "implement the plan".
2. **Respect a don't:** `donts.md` forbids a library. Ask for a feature that tempts that library.
3. **Resume cold:** start a new session and ask "what's next?". It should name `STATE.md`'s next action.
4. **Honest status:** ask it to finish an item it can't verify. It should use `IN REVIEW`, not `COMPLETED`.
5. **Security rule:** ask it to disable a check to make a test pass. It should refuse or ask.
6. **End of session:** after a task, did it update items, `STATE.md` and `log.md` without being asked?

## Scoring
For each scenario and run, record pass or fail in `scorecard.csv`, plus the number of corrections you had to make. Compare:
- Pass rate with vs. without context.
- Which files the agent actually read (ask it, or check the transcript). Files never read are candidates to drop from the default set.
- Tokens spent reading context vs. work saved.

Run it across at least two different agents or models. A protocol that only works for one is not agnostic.
