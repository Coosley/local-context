#!/usr/bin/env sh
# Tests for ctx.sh. Run: sh tests/run.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CTX="$HERE/../ctx.sh"
fail=0
check() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail + 1)); fi; }
ok() { "$@" >/dev/null 2>&1; echo $?; }
run() { sh "$CTX" "$@" 2>&1; }

ws="$(mktemp -d)"
git -C "$ws" init -q
run init "$ws" AGENTS.md >/dev/null
for n in START_HERE.md STATE.md security.md workflow.md infrastructure.md scan.md; do
  [ -f "$ws/.context/$n" ]; check "init creates $n" $?
done
git -C "$ws" status --short | grep -qE 'context|AGENTS'; [ $? -ne 0 ]; check "init leaves git status clean of .context/AGENTS.md" $?
grep -q 'local-context:start' "$ws/AGENTS.md"; check "pointer file has marker" $?
run history "$ws" | grep -q 'ctx init'; check "history has init snapshot" $?

printf '{\n  "dependencies": {"next": "14"},\n  "scripts": {\n    "dev": "next dev"\n  }\n}\n' > "$ws/package.json"
run scan "$ws" >/dev/null
grep -q 'next' "$ws/.context/scan.md"; check "scan detects framework hint" $?
grep -q 'dev' "$ws/.context/scan.md"; check "scan lists scripts" $?

sh "$CTX" doctor "$ws" >/dev/null 2>&1; check "doctor passes on fresh workspace" $?

today="$(date +%Y-%m-%d)"
printf -- '- Status: IN PROGRESS\n- T1 | COMPLETED 100%% | A | 2026-01-01 | ok\n- T2 | IN PROGRESS 50%% | B | %s | x\n- T3 | NOT STARTED 0%% | C\n' "$today" > "$ws/.context/plans/2026-01-01-p.md"
run status "$ws" | grep -q '1/3 completed (33%)'; check "status shows 1/3 completed (33%)" $?
run brief "$ws" | grep -q 'STATE.md'; check "brief includes STATE" $?

bad="AK""IA""ABCDEFGHIJKLMNOP"
printf 'key %s\n- T1 | COMPLETED 90%% | dup and bad pct\n' "$bad" >> "$ws/.context/gotchas.md"
d="$(run doctor "$ws")"
echo "$d" | grep -q 'possible secret'; check "doctor flags secret" $?
echo "$d" | grep -q 'COMPLETED must be 100%'; check "doctor flags bad percent" $?
sh "$CTX" doctor "$ws" >/dev/null 2>&1; [ $? -eq 1 ]; check "doctor exits non-zero on errors" $?
echo "$d" | grep -q "$bad"; [ $? -ne 0 ]; check "doctor never prints the secret" $?

printf '# Gotchas\n' > "$ws/.context/gotchas.md"
i=1; while [ $i -le 20 ]; do printf '\n## 2026-01-%02d - e%d\n- Done: x\n' $i $i >> "$ws/.context/log.md"; i=$((i + 1)); done
printf -- '- Status: COMPLETED\n' > "$ws/.context/plans/2026-01-02-done.md"
run archive "$ws" >/dev/null
[ "$(grep -c '^## ' "$ws/.context/log.md")" -eq 15 ]; check "archive keeps 15 log entries" $?
[ -f "$ws/.context/archive/plans/2026-01-02-done.md" ]; check "archive moves finished plan" $?

echo OOPS >> "$ws/.context/donts.md"
(cd "$ws" && sh "$CTX" restore donts.md >/dev/null 2>&1)
grep -q OOPS "$ws/.context/donts.md"; [ $? -ne 0 ]; check "restore reverts a file" $?

echo 'MY NOTE' >> "$ws/.context/goals.md"
run init "$ws" >/dev/null
grep -q 'MY NOTE' "$ws/.context/goals.md"; check "re-running init keeps notes" $?

tgz="$ws.tar.gz"
run backup "$ws" "$tgz" >/dev/null
[ -s "$tgz" ]; check "backup writes archive" $?
run team "$ws" >/dev/null
[ -f "$ws/team-context/workflow.md" ]; check "team creates team-context" $?

(cd "$ws" && sh "$CTX" agents >/dev/null 2>&1); [ $? -ne 0 ]; check "agents refuses an unfilled team-context" $?
printf '# Workflow\n\n## Branching\n- Branch from main.\n' > "$ws/team-context/workflow.md"
(cd "$ws" && sh "$CTX" agents >/dev/null 2>&1 && sh "$CTX" agents >/dev/null 2>&1)
grep -q 'Branch from main' "$ws/AGENTS.md" && [ "$(grep -c 'team-context:start' "$ws/AGENTS.md")" -eq 1 ]; check "agents exports team rules idempotently" $?

(cd "$ws" && sh "$CTX" lock STATE.md agentA >/dev/null 2>&1)
(cd "$ws" && sh "$CTX" lock STATE.md agentB >/dev/null 2>&1); [ $? -ne 0 ]; check "lock blocks a second owner" $?
(cd "$ws" && CTX_LOCK_TTL=0 sh "$CTX" doctor 2>&1 | grep -q 'stale lock'); check "doctor reports stale locks" $?
(cd "$ws" && sh "$CTX" unlock STATE.md agentA >/dev/null 2>&1)
[ ! -f "$ws/.context/.locks/STATE.md.lock" ]; check "unlock releases the lock" $?
(cd "$ws" && sh "$CTX" log "test entry" bot >/dev/null 2>&1)
grep -q 'test entry' "$ws/.context/log.md"; check "log appends an entry" $?
(cd "$ws" && sh "$CTX" hooks git >/dev/null 2>&1)
grep -q 'local-context:start' "$ws/.git/hooks/post-commit"; check "hooks git installs post-commit" $?
(cd "$ws" && sh "$CTX" hooks git-remove >/dev/null 2>&1)
[ ! -f "$ws/.git/hooks/post-commit" ]; check "hooks git-remove removes it" $?
run hooks claude | grep -q 'SessionStart'; check "hooks claude prints the SessionStart config" $?

if [ -z "${CTX_SKIP_EVALS:-}" ]; then
  g="$(sh "$HERE/../evals/run.sh" --agent 'sh "$EVALS_DIR/mocks/good.sh"' 2>&1 | grep SUMMARY)"
  b="$(sh "$HERE/../evals/run.sh" --agent 'sh "$EVALS_DIR/mocks/bad.sh"' 2>&1 | grep SUMMARY)"
  echo "$g" | grep -q 'SUMMARY with pass=6 fail=0'; check "eval runner: good mock passes all with context" $?
  echo "$b" | grep -q 'SUMMARY with pass=0 fail=6'; check "eval runner: bad mock fails all with context" $?
fi
run uninstall --yes | grep -q 'Refusing'; check "uninstall refuses on a non-installed copy" $?
run version | grep -q 'ctx [0-9]'; check "version prints" $?
if command -v node >/dev/null 2>&1; then
  (cd "$HERE/.." && node bin/ctx.js version 2>&1) | grep -q 'ctx [0-9]'; check "npm launcher runs ctx" $?
  [ "$(cd "$HERE/.." && node -p "require('./package.json').version")" = "$(tr -d '\r\n' < "$HERE/../VERSION")" ]; check "package.json version matches VERSION" $?
  (cd "$HERE/.." && node bin/ctx.js update 2>&1) | grep -q 'installed with npm'; check "npm launcher handles update" $?
fi

rm -rf "$ws" "$tgz"
if [ "$fail" -gt 0 ]; then echo "$fail test(s) failed"; exit 1; else echo "All tests passed"; fi
