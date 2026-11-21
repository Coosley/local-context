# Workflow (teams and branches)

`.context/` is local to this clone: teammates don't see it. The team's canonical rules live in the repo (CONTRIBUTING.md, CODEOWNERS, CI config, branch protection). This file summarizes them for agents. If they differ, the repo wins.

## Team
- Working solo or in a team: <solo | team of N>
- Roles / owners: <who reviews what, CODEOWNERS path>

## Branching rules
- Default / protected branches: <main, release/*>
- No direct commits to protected branches: <yes/no>
- Branch naming: <feature/<slug>, fix/<slug>, ...>
- Base branch for new work: <main | develop>
- Merge strategy: <squash | merge | rebase>
- Never: force-push shared branches, rewrite shared history, or merge without being asked.

## Commits and PRs
- Commit message style: <conventional commits / other>
- PR requirements: <reviewers, checks that must pass, linked issue, template>
- Release / tagging process: <...>

## Active branches
| Branch | Purpose | Plan | Status | Base |
|---|---|---|---|---|
| <branch> | <what it is for> | plans/<file>.md | <active / in review / merged> | <main> |

## Rules for agents
- At session start, record the current branch in `STATE.md` and work only on that branch's plan.
- This folder is not switched by `git checkout`. An item marked `[x]` on another branch may be absent here: verify in the code before relying on it.
- Update the table above when a branch is created, goes to review, or is merged. After a merge, mark its plan `done`.
- Run the project's checks before proposing a merge: `<test / lint / security commands>`.
