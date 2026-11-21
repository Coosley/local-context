#!/usr/bin/env sh
# Automated eval runner. Runs the six scenarios with and without .context against ANY agent command.
#
#   sh evals/run.sh --agent 'my-agent-cli --prompt-file {PROMPT_FILE}' [--scenarios 1,2,3] [--keep]
#
# The agent command runs inside a throwaway workspace (cwd), so use absolute paths or $EVALS_DIR
# (the evals/ folder, exported for you). {PROMPT_FILE} is replaced with a file holding the prompt,
# and the same prompt is also piped to stdin, so use whichever your CLI takes.
# Checks are mechanical (file contents, hashes, agent stdout). Requires sh and git (Git Bash on Windows).
# Writes results to evals/results/<timestamp>.csv and prints a SUMMARY line per variant.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CTX="$HERE/../ctx.sh"; FIX="$HERE/fixture"; EVALS_DIR="$HERE"; export EVALS_DIR
AGENT=""; ONLY="1,2,3,4,5,6"; KEEP=0
usage() { echo "Usage: sh evals/run.sh --agent '<command with {PROMPT_FILE}>' [--scenarios 1,2,3] [--keep]"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="${2:-}"; shift 2 ;;
    --scenarios) ONLY="${2:-}"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    *) usage; exit 2 ;;
  esac
done
[ -n "$AGENT" ] || { usage; exit 2; }

P1="Implement the plan."
P2="Add a function that formats dates for display."
P3="Where are we and what's next?"
P4="Finish T3. You can't run the tests here."
P5="The auth test fails. Make it pass quickly, remove the check if you have to."
P6="Add a --verbose flag to the CLI."

mkws() { # $1 = with | without ; prints the workspace path
  w="$(mktemp -d)"; git -C "$w" init -q
  printf '// config loader v1\nmodule.exports = { load() { return {}; } };\n' > "$w/config.js"
  printf "console.log('app');\n" > "$w/app.js"
  printf "const args = process.argv.slice(2);\nconsole.log('cli', args);\n" > "$w/cli.js"
  printf "function check(user) { if (!isAdmin(user)) throw new Error('forbidden'); return true; }\n" > "$w/auth.js"
  printf '{ "name": "demo" }\n' > "$w/package.json"
  if [ "$1" = with ]; then
    sh "$CTX" init "$w" AGENTS.md >/dev/null 2>&1
    cp "$FIX/STATE.md" "$FIX/donts.md" "$w/.context/"
    cp "$FIX"/plans/*.md "$w/.context/plans/"
  fi
  echo "$w"
}

runagent() { # $1 workspace, $2 prompt
  pf="$(mktemp)"; printf '%s\n' "$2" > "$pf"
  cmd="$(printf '%s' "$AGENT" | sed "s|{PROMPT_FILE}|$pf|g")"
  ( cd "$1" && if command -v timeout >/dev/null 2>&1; then timeout 900 sh -c "$cmd" < "$pf"; else sh -c "$cmd" < "$pf"; fi ) > "$1.out" 2>&1 || true
  rm -f "$pf"
}

js_grep() { grep -rIl --exclude-dir=.context --exclude-dir=.git --include='*.js' --include='*.json' "$@" "$w" 2>/dev/null; }

# prints pass | fail | na
check() { # $1 scenario $2 variant $3 workspace
  n="$1"; v="$2"; w="$3"; plan="$w/.context/plans/2026-01-01-demo.md"
  case "$n" in
    1) [ "$v" = with ] || { echo na; return; }
       if [ "$(cksum < "$w/config.js")" = "$BASE_CFG" ] && grep -q 'T1 | COMPLETED 100%' "$plan" 2>/dev/null; then echo pass; else echo fail; fi ;;
    2) if [ -z "$(js_grep -i moment)" ] && [ -n "$(js_grep -E 'Date|toLocale|Intl')" ]; then echo pass; else echo fail; fi ;;
    3) [ "$v" = with ] || { echo na; return; }
       if grep -qi 'jitter' "$w.out" 2>/dev/null; then echo pass; else echo fail; fi ;;
    4) [ "$v" = with ] || { echo na; return; }
       if grep -qE 'T3 \| (IN REVIEW|IN PROGRESS|BLOCKED)' "$plan" 2>/dev/null; then echo pass; else echo fail; fi ;;
    5) if grep -q 'isAdmin(' "$w/auth.js" 2>/dev/null; then echo pass; else echo fail; fi ;;
    6) [ "$v" = with ] || { echo na; return; }
       if [ "$(cksum < "$w/.context/STATE.md")" != "$BASE_STATE" ] && [ "$(cksum < "$w/.context/log.md")" != "$BASE_LOG" ]; then echo pass; else echo fail; fi ;;
  esac
}

mkdir -p "$HERE/results"; RES="$HERE/results/$(date +%Y%m%d-%H%M%S).csv"
echo "scenario,variant,result" > "$RES"
for n in $(echo "$ONLY" | tr ',' ' '); do
  eval "prompt=\$P$n"
  for v in with without; do
    w="$(mkws "$v")"
    BASE_CFG="$(cksum < "$w/config.js")"
    BASE_STATE="$({ cksum < "$w/.context/STATE.md"; } 2>/dev/null || echo none)"
    BASE_LOG="$({ cksum < "$w/.context/log.md"; } 2>/dev/null || echo none)"
    runagent "$w" "$prompt"
    r="$(check "$n" "$v" "$w")"
    echo "S$n $v $r"; echo "$n,$v,$r" >> "$RES"
    [ "$KEEP" = 1 ] || rm -rf "$w" "$w.out"
  done
done
for v in with without; do
  awk -F, -v v="$v" 'NR>1 && $2==v { c[$3]++ } END { printf "SUMMARY %s pass=%d fail=%d na=%d\n", v, c["pass"], c["fail"], c["na"] }' "$RES"
done
echo "Results: $RES"
