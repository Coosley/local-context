#!/usr/bin/env sh
# ctx - harness-agnostic local context (a git-ignored .context/ brain per workspace). POSIX sh.
# Usage: ctx <command> [path] ...   (run `ctx help`)
set -eu

self="$0"
while [ -h "$self" ]; do
  d="$(cd "$(dirname "$self")" && pwd)"; self="$(readlink "$self")"
  case "$self" in /*) ;; *) self="$d/$self" ;; esac
done
HOME_DIR="$(cd "$(dirname "$self")" && pwd)"
SRC="$HOME_DIR/templates"
BOOT="Read .context/START_HERE.md and follow it. It is this workspace's local project memory."
ALWAYS="STATE.md donts.md preferences.md security.md"
JD='function jd(y,m,d,  a,yy,mm){ a=int((14-m)/12); yy=y+4800-a; mm=m+12*a-3; return d+int((153*mm+2)/5)+365*yy+int(yy/4)-int(yy/100)+int(yy/400)-32045 }'
SECRET_A='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.'
SECRET_B="(password|passwd|secret|api[_-]?key|token)[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9/+_-]{12,}"

cmd="${1:-help}"; [ $# -gt 0 ] && shift
ws="${1:-.}"; [ $# -gt 0 ] && shift

has_git() { command -v git >/dev/null 2>&1; }
need_ctx() {
  ws="$(cd "$ws" && pwd)"; ctx="$ws/.context"
  [ -d "$ctx" ] || { echo "No .context in $ws. Run: ctx init"; exit 1; }
}
exclude_file() {
  has_git || return 1
  g="$(git -C "$ws" rev-parse --git-path info/exclude 2>/dev/null)" || return 1
  case "$g" in /*|[A-Za-z]:*) echo "$g";; *) echo "$ws/$g";; esac
}
add_exclude() {
  f="$(exclude_file)" || return 1
  mkdir -p "$(dirname "$f")"
  grep -qxF "$1" "$f" 2>/dev/null || echo "$1" >> "$f"
}
snapshot() {
  has_git || return 1
  [ -d "$ctx/.git" ] || git -C "$ctx" init -q >/dev/null 2>&1
  [ -f "$ctx/.gitignore" ] || printf '.locks/\n' > "$ctx/.gitignore"
  git -C "$ctx" add -A >/dev/null 2>&1
  [ -n "$(git -C "$ctx" status --porcelain 2>/dev/null)" ] || return 1
  git -C "$ctx" -c user.name=ctx -c user.email=ctx@localhost -c commit.gpgsign=false commit -q --no-verify -m "$1" >/dev/null 2>&1
}
ctx_files() {
  find "$ctx" -name '*.md' ! -path '*/archive/*' ! -path '*/.git/*' ! -name '_template.md' ! -name START_HERE.md ! -name scan.md | sort
}

LOCK_TTL="${CTX_LOCK_TTL:-600}"
lockfile() { mkdir -p "$ctx/.locks"; echo "$ctx/.locks/$(printf '%s' "$1" | tr '/\\: ' '____').lock"; }

progress() {
  ctx_files | while read -r f; do
    awk -v name="${f#"$ctx"/}" '
    BEGIN { ok = " NOT STARTED , IN PROGRESS , IN REVIEW , BLOCKED , FAILED , ABANDONED , COMPLETED " }
    /^[ \t]*- [^ |]+ *\|/ {
      n = split($0, a, "|"); st = a[2]; gsub(/^ +| +$/, "", st); sub(/ +[0-9]+%.*$/, "", st)
      if (index(ok, " " st " ") == 0) next
      t = a[3]; gsub(/^ +| +$/, "", t); if (t ~ /^<[^>]*>$/) next
      tot++; c[st]++
      if (st != "COMPLETED" && st != "ABANDONED") { l = $0; sub(/^[ \t]+/, "", l); open[++k] = l }
    }
    END {
      if (!tot) exit
      den = tot - c["ABANDONED"]; p = den ? int(100 * c["COMPLETED"] / den + 0.5) : 0
      printf "%s: %d/%d completed (%d%%)\n", name, c["COMPLETED"], den, p
      for (i = 1; i <= k; i++) print "  " open[i]
    }' "$f"
  done
}

doctor() {
  out="$(mktemp)"; today="$(date +%Y-%m-%d)"
  for n in START_HERE.md STATE.md goals.md todo.md donts.md preferences.md security.md log.md; do
    [ -f "$ctx/$n" ] || echo "WARN  $n: missing (run ctx init to restore templates)" >> "$out"
  done
  ctx_files | while read -r f; do
    rel="${f#"$ctx"/}"
    awk -v name="$rel" -v today="$today" "$JD"'
    BEGIN { split(today, T, "-"); tj = jd(T[1]+0, T[2]+0, T[3]+0) }
    /^[ \t]*- [^ |]+[ \t]*\|/ {
      if ($0 !~ /^[ \t]*- [^ |]+[ \t]*\|[ \t]*(NOT STARTED|IN PROGRESS|IN REVIEW|BLOCKED|FAILED|ABANDONED|COMPLETED)[ \t]+[0-9]+%/) {
        print "ERROR " name ":" NR ": malformed item line (expected: - ID | STATUS PCT% | title | date | note)"; next }
      n = split($0, a, "|")
      id = a[1]; sub(/^[ \t]*- /, "", id); gsub(/[ \t]+/, "", id)
      st = a[2]; gsub(/^ +| +$/, "", st); p = st; sub(/^.*[ \t]/, "", p); sub(/%.*/, "", p); p += 0; sub(/[ \t]+[0-9]+%.*$/, "", st)
      t = a[3]; gsub(/^ +| +$/, "", t); if (t ~ /^<[^>]*>$/) next
      if (seen[id]++) print "ERROR " name ":" NR ": duplicate ID " id
      if (st == "NOT STARTED" && p != 0) print "ERROR " name ":" NR ": " id " NOT STARTED must be 0%"
      if (st == "COMPLETED" && p != 100) print "ERROR " name ":" NR ": " id " COMPLETED must be 100%"
      if (st == "IN PROGRESS" && (p < 1 || p > 99)) print "ERROR " name ":" NR ": " id " IN PROGRESS must be 1-99%"
      if (p > 100) print "ERROR " name ":" NR ": " id " percent over 100"
      d = a[4]; gsub(/^ +| +$/, "", d); nt = a[5]; gsub(/^ +| +$/, "", nt)
      if (st == "COMPLETED" && (d == "" || nt == "")) print "WARN  " name ":" NR ": " id " COMPLETED without date/evidence"
      if ((st == "FAILED" || st == "ABANDONED" || st == "BLOCKED") && nt == "") print "WARN  " name ":" NR ": " id " " st " without a reason in the note"
      if (st == "IN PROGRESS" && d ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
        split(d, D, "-"); age = tj - jd(D[1]+0, D[2]+0, D[3]+0)
        if (age > 14) print "WARN  " name ":" NR ": " id " IN PROGRESS untouched for " age " days"
      }
    }' "$f" >> "$out"
    lines="$(wc -l < "$f" | tr -d ' ')"; base="$(basename "$f")"
    limit=400; [ "$base" = STATE.md ] && limit=40; [ "$base" = log.md ] && limit=300
    [ "$lines" -le "$limit" ] || echo "WARN  $rel: $lines lines (budget $limit); run ctx archive or trim" >> "$out"
  done
  find "$ctx" -type f ! -path '*/.git/*' ! -path '*/.locks/*' ! -name '*.zip' ! -name '*.gz' | sort | while read -r f; do
    rel="${f#"$ctx"/}"
    { grep -nIE "$SECRET_A" "$f" 2>/dev/null; grep -nIiE "$SECRET_B" "$f" 2>/dev/null; } | cut -d: -f1 | sort -un | while read -r n; do
      echo "ERROR $rel:$n: possible secret (value hidden). Remove it and rotate it" >> "$out"
    done
  done
  if [ -d "$ctx/.locks" ]; then
    now="$(date +%s)"
    for l in "$ctx"/.locks/*.lock; do
      [ -f "$l" ] || continue
      lo="$(cut -d'|' -f1 "$l")"; lt="$(cut -d'|' -f2 "$l")"; la=$((now - lt))
      if [ "$la" -gt "$LOCK_TTL" ]; then echo "WARN  .locks/$(basename "$l"): stale lock held by $lo (${la}s old); remove with ctx unlock" >> "$out"
      else echo "INFO  .locks/$(basename "$l"): held by $lo (${la}s)" >> "$out"; fi
    done
  fi
  if [ -f "$ctx/STATE.md" ]; then
    ds="$(sed -n 's/^Last updated: *\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\).*/\1/p' "$ctx/STATE.md" | head -1)"
    if [ -n "$ds" ]; then
      age="$(awk -v today="$today" -v d="$ds" "$JD"' BEGIN { split(today,T,"-"); split(d,D,"-"); print jd(T[1]+0,T[2]+0,T[3]+0) - jd(D[1]+0,D[2]+0,D[3]+0) }')"
      [ "$age" -le 7 ] || echo "WARN  STATE.md: last updated $age days ago" >> "$out"
    else echo "INFO  STATE.md: still a template (no Last updated date)" >> "$out"; fi
  fi
  chars=0
  for n in $ALWAYS; do [ -f "$ctx/$n" ] && chars=$((chars + $(wc -c < "$ctx/$n" | tr -d ' '))); done
  tok=$((chars / 4)); lvl="INFO "; [ "$tok" -le 3000 ] || lvl="WARN "
  echo "$lvl budget: Always tier is about $tok tokens (target under 3000)" >> "$out"
  un="$(ctx_files | while read -r f; do [ "$(basename "$f")" = README.md ] && continue; grep -qE '<[^>]{2,}>' "$f" && echo "${f#"$ctx"/}"; done | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  [ -z "$un" ] || echo "INFO  templates: placeholders remain in: $un" >> "$out"
  cat "$out"
  errs="$(grep -c '^ERROR' "$out" || true)"; warns="$(grep -c '^WARN' "$out" || true)"
  rm -f "$out"
  echo "doctor: $errs error(s), $warns warning(s)"
  DOCTOR_ERRS="$errs"
}

archive() {
  snapshot "pre-archive" || true
  keep=15; me=0; mp=0
  if [ -f "$ctx/log.md" ]; then
    total="$(grep -c '^## ' "$ctx/log.md" || true)"
    if [ "$total" -gt "$keep" ]; then
      cut=$((total - keep)); mkdir -p "$ctx/archive"
      awk -v cut="$cut" -v arch="$ctx/archive/log.md" -v keepf="$ctx/log.md.new" '
        /^## / { n++ }
        n >= 1 && n <= cut { print >> arch; next }
        { print > keepf }' "$ctx/log.md"
      mv "$ctx/log.md.new" "$ctx/log.md"; me=$cut
    fi
  fi
  if [ -d "$ctx/plans" ]; then
    for pf in "$ctx"/plans/*.md; do
      [ -f "$pf" ] || continue
      [ "$(basename "$pf")" = _template.md ] && continue
      if grep -qE '^[[:space:]]*-[[:space:]]+Status:[[:space:]]*(COMPLETED|ABANDONED)' "$pf"; then
        mkdir -p "$ctx/archive/plans"; mv "$pf" "$ctx/archive/plans/"; mp=$((mp + 1))
      fi
    done
  fi
  snapshot "archive" || true
  echo "Archived $me log entries and $mp plan(s) into .context/archive/."
}

scan() {
  list="$(mktemp)"
  if has_git && git -C "$ws" rev-parse --git-dir >/dev/null 2>&1; then git -C "$ws" ls-files -co --exclude-standard > "$list"
  else (cd "$ws" && find . -type f ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/dist/*' ! -path '*/build/*' ! -path '*/venv/*' ! -path '*/.venv/*' ! -path '*/target/*' ! -path '*/vendor/*' ! -path '*/.context/*' ! -path '*/__pycache__/*' | sed 's|^\./||') > "$list"; fi
  o="$ctx/scan.md"
  {
    echo "# Scan (auto-generated, facts only)"; echo
    echo "Generated by \`ctx scan\` on $(date +%Y-%m-%d). Overwritten on every scan. Verify in the code before relying on it, then copy confirmed facts into the other files."
    echo; echo "## Workspace"
    echo "- Name: $(basename "$ws")"
    echo "- Files (excluding ignored): $(wc -l < "$list" | tr -d ' ')"
    tops="$(grep '/' "$list" | cut -d/ -f1 | sort -u | head -25 | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    [ -z "$tops" ] || echo "- Top-level folders: $tops"
    if has_git && git -C "$ws" rev-parse --git-dir >/dev/null 2>&1; then
      echo; echo "## Git"
      br="$(git -C "$ws" branch --show-current 2>/dev/null || true)"
      echo "- Current branch: ${br:-(detached or none)}"
      rem="$(git -C "$ws" remote -v 2>/dev/null | grep '(fetch)' | sed 's|//[^/@ ]*@|//|' | tr '\n' ';' | sed 's/;$//')"
      [ -z "$rem" ] || echo "- Remotes: $rem"
      lb="$(git -C "$ws" branch --format='%(refname:short)' 2>/dev/null | head -10 | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
      [ -z "$lb" ] || echo "- Local branches: $lb"
    fi
    echo; echo "## Languages (by file extension)"
    sed -n 's/.*\.\([A-Za-z0-9]\{1,\}\)$/\1/p' "$list" | tr 'A-Z' 'a-z' | grep -vxE 'md|json|lock|txt|svg|png|jpg|ico|map' | sort | uniq -c | sort -rn | head -8 | awk '{print "- ." $2 ": " $1}'
    echo; echo "## Manifests and stack hints"
    blob="$(mktemp)"
    for pair in package.json:Node/JS pyproject.toml:Python requirements.txt:Python Pipfile:Python go.mod:Go Cargo.toml:Rust pom.xml:Java-Maven build.gradle:Java/Kotlin-Gradle Gemfile:Ruby composer.json:PHP mix.exs:Elixir deno.json:Deno tsconfig.json:TypeScript; do
      m="${pair%%:*}"; lbl="${pair#*:}"
      hit="$(grep -E "(^|/)$(echo "$m" | sed 's/\./\\./g')\$" "$list" | head -5 | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
      if [ -n "$hit" ]; then
        echo "- $m ($lbl): $hit"
        first="$(echo "$hit" | cut -d, -f1)"; [ -f "$ws/$first" ] && cat "$ws/$first" >> "$blob"
      fi
    done
    csp="$(grep -E '\.(csproj|sln)$' "$list" | head -5 | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    [ -z "$csp" ] || echo "- .NET: $csp"
    fw=""
    for t in next react vue svelte angular express fastify nestjs vite tailwindcss prisma drizzle-orm django flask fastapi rails laravel spring-boot gin-gonic axum actix; do
      grep -qiE "(^|[^a-z0-9_-])$t([^a-z0-9_-]|\$)" "$blob" 2>/dev/null && fw="$fw${fw:+, }$t"
    done
    [ -z "$fw" ] || echo "- Framework/library hints (verify): $fw"
    rm -f "$blob"
    if [ -f "$ws/package.json" ] && grep -q '"scripts"' "$ws/package.json"; then
      echo; echo "## package.json scripts"
      sed -n '/"scripts"[[:space:]]*:/,/}/p' "$ws/package.json" | sed '1d;$d' | sed 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*:[[:space:]]*"\(.*\)",\{0,1\}$/- \1: `\2`/'
    fi
    echo; echo "## CI, infrastructure and security files"
    for pair in 'Dockerfile|(^|/)Dockerfile' 'docker-compose|docker-compose.*\.ya?ml$' 'GitHub Actions|^\.github/workflows/' 'GitLab CI|\.gitlab-ci\.yml$' 'Vercel|(^|/)vercel\.json$' 'Netlify|(^|/)netlify\.toml$' 'Cloudflare (wrangler)|(^|/)wrangler\.(toml|jsonc?)$' 'Fly.io|(^|/)fly\.toml$' 'Render|(^|/)render\.yaml$' 'Procfile|(^|/)Procfile$' 'Terraform|\.tf$' 'Kubernetes/Helm|(^|/)(k8s|helm|charts)/' 'Serverless|(^|/)serverless\.ya?ml$' 'env example|(^|/)\.env(\.[a-z]+)?\.(example|sample)$' 'CODEOWNERS|(^|/)CODEOWNERS$' 'SECURITY.md|(^|/)SECURITY\.md$' 'CONTRIBUTING.md|(^|/)CONTRIBUTING\.md$' 'pre-commit|\.pre-commit-config\.yaml$' 'Dependabot/Renovate|(dependabot\.ya?ml|renovate\.json)$' 'Lint/format config|(^|/)(\.eslintrc.*|eslint\.config\..*|\.prettierrc.*|ruff\.toml|\.golangci\.ya?ml|rustfmt\.toml|\.editorconfig)$' 'Tests|(^|/)(tests?|__tests__|spec|e2e)/'; do
      lbl="${pair%%|*}"; pat="${pair#*|}"
      cnt="$(grep -cE "$pat" "$list" || true)"
      if [ "$cnt" -gt 0 ]; then
        shown="$(grep -E "$pat" "$list" | head -3 | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
        extra=""; [ "$cnt" -gt 3 ] && extra=" (+$((cnt - 3)) more)"
        echo "- $lbl: $shown$extra"
      fi
    done
    envf="$(grep -E '(^|/)\.env$' "$list" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    [ -z "$envf" ] || { echo; echo "- WARNING: .env file(s) not ignored by git: $envf. Add them to .gitignore."; }
  } > "$o"
  rm -f "$list"
}

case "$cmd" in
  init)
    ws="$(cd "$ws" && pwd)"; ctx="$ws/.context"; mkdir -p "$ctx"
    (cd "$SRC" && find . -type f) | while read -r rel; do
      mkdir -p "$ctx/$(dirname "$rel")"
      [ -e "$ctx/$rel" ] || cp "$SRC/$rel" "$ctx/$rel"
    done
    cp "$SRC/START_HERE.md" "$ctx/START_HERE.md"
    if add_exclude ".context/"; then echo "Excluded via .git/info/exclude (local only, nothing committed)."; else echo "Not a git repo: nothing to exclude yet. Re-run init after 'git init'."; fi
    for p in "$@"; do
      pf="$ws/$p"
      if [ -f "$pf" ] && grep -q 'local-context:start' "$pf"; then continue; fi
      printf '\n<!-- local-context:start -->\n%s\n<!-- local-context:end -->\n' "$BOOT" >> "$pf"
      if ! git -C "$ws" ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then add_exclude "$p" || true
      else echo "warning: $p is tracked by git; the pointer block will show as a change."; fi
    done
    scan
    snapshot "ctx init" && echo "Snapshot history started (ctx history)." || true
    echo "Context ready: $ctx"
    echo "Repo facts written to .context/scan.md."
    echo; echo "Next, paste into ANY agent/harness (or its instruction file):"; echo "  $BOOT"
    echo "To have the agent fill the files from this repo, run: ctx bootstrap"
    ;;
  status) need_ctx; cat "$ctx/STATE.md"; echo; echo "--- Progress ---"; progress ;;
  brief)
    need_ctx
    br=""; has_git && br="$(git -C "$ws" branch --show-current 2>/dev/null || true)"
    echo "# Local context brief: $(basename "$ws")${br:+ (branch $br)}"
    echo "Full protocol: .context/START_HERE.md. Read other files only when relevant."
    [ -d "$ws/team-context" ] && echo "Team rules: read team-context/ first (committed, shared, wins over personal context)."
    for n in $ALWAYS; do [ -f "$ctx/$n" ] && { echo; echo "## .context/$n"; cat "$ctx/$n"; }; done
    echo; echo "## Progress"; progress
    echo; echo "Before finishing: update item statuses, STATE.md and log.md, then run: ctx wrap"
    ;;
  doctor) need_ctx; DOCTOR_ERRS=0; doctor; [ "$DOCTOR_ERRS" -eq 0 ] || exit 1 ;;
  wrap)
    need_ctx; DOCTOR_ERRS=0; doctor
    if snapshot "ctx wrap"; then echo "Snapshot saved."; else echo "No changes to snapshot."; fi
    [ "$DOCTOR_ERRS" -eq 0 ] || { echo "Fix the errors above, then run ctx wrap again."; exit 1; }
    ;;
  archive) need_ctx; archive ;;
  scan) need_ctx; scan; echo "Wrote .context/scan.md" ;;
  bootstrap)
    need_ctx; scan
    cat <<'EOF'
Paste this to your agent:

Bootstrap this workspace's local context. Read .context/START_HERE.md and .context/scan.md. Verify the scan's facts in the code. Then fill in architecture.md, conventions.md, deployment.md, infrastructure.md and security.md (derive security practices from the stack), design.md if there is a UI, and STATE.md and goals.md after asking me at most five short questions. Do not invent facts: write "unknown" where you cannot tell. When done, run ctx doctor if available and show me a summary of what you filled in and what is still unknown.
EOF
    ;;
  snapshot) need_ctx; m="${1:-manual snapshot}"; if snapshot "$m"; then echo "Snapshot saved: $m"; else echo "No changes (or git missing)."; fi ;;
  history) need_ctx; git -C "$ctx" log --oneline -n 30 ;;
  restore)
    file="$ws"; rev="${1:-}"; ws="."; need_ctx
    [ "$file" != "." ] || { echo "Usage: ctx restore <file> [rev]   (run in the workspace; see ctx history)"; exit 1; }
    [ -z "$rev" ] || snapshot "pre-restore" || true
    if git -C "$ctx" checkout "${rev:-HEAD}" -- "$file" >/dev/null 2>&1; then echo "Restored $file from ${rev:-HEAD}."; else echo "Could not restore $file from ${rev:-HEAD}."; exit 1; fi
    ;;
  backup)
    need_ctx; dest="${1:-}"
    if [ -z "$dest" ]; then mkdir -p "$HOME/.local-context-backups"; dest="$HOME/.local-context-backups/$(basename "$ws")-$(date +%Y%m%d-%H%M%S).tar.gz"; fi
    tar -czf "$dest" -C "$ws" .context && echo "Backup written: $dest"
    ;;
  team)
    ws="$(cd "$ws" && pwd)"; td="$ws/team-context"; mkdir -p "$td"
    [ -e "$td/README.md" ] || cp "$HOME_DIR/team-templates/README.md" "$td/README.md"
    for n in workflow.md security.md conventions.md; do [ -e "$td/$n" ] || cp "$SRC/$n" "$td/$n"; done
    echo "Created $td. Review it, then commit it: it is shared with your team (unlike .context/)."
    ;;
  lock)
    file="$ws"; owner="${1:-${USER:-agent}}"; ws="."; need_ctx
    [ "$file" != "." ] || { echo "Usage: ctx lock <file> [owner]   (run in the workspace)"; exit 1; }
    lf="$(lockfile "$file")"; now="$(date +%s)"
    if [ -f "$lf" ]; then
      holder="$(cut -d'|' -f1 "$lf")"; ts="$(cut -d'|' -f2 "$lf")"; age=$((now - ts))
      if [ "$holder" != "$owner" ] && [ "$age" -lt "$LOCK_TTL" ]; then echo "$file is locked by $holder (${age}s ago). Wait, or ask them to run: ctx unlock $file"; exit 1; fi
      rm -f "$lf"
    fi
    if ( set -C; printf '%s|%s\n' "$owner" "$now" > "$lf" ) 2>/dev/null; then
      echo "Locked $file for $owner (stale after ${LOCK_TTL}s; re-run to refresh). Release with: ctx unlock $file"
    else echo "$file was just locked by someone else."; exit 1; fi
    ;;
  unlock)
    file="$ws"; owner="${1:-}"; ws="."; need_ctx
    [ "$file" != "." ] || { echo "Usage: ctx unlock <file> [owner|--force]"; exit 1; }
    lf="$(lockfile "$file")"
    [ -f "$lf" ] || { echo "$file is not locked."; exit 0; }
    holder="$(cut -d'|' -f1 "$lf")"
    if [ -z "$owner" ] || [ "$owner" = "--force" ] || [ "$owner" = "$holder" ]; then rm -f "$lf"; echo "Unlocked $file."
    else echo "$file is locked by $holder. Use --force to override."; exit 1; fi
    ;;
  locks)
    need_ctx; found=0; now="$(date +%s)"
    for l in "$ctx"/.locks/*.lock; do
      [ -f "$l" ] || continue
      found=1; lo="$(cut -d'|' -f1 "$l")"; lt="$(cut -d'|' -f2 "$l")"; la=$((now - lt)); stale=""
      [ "$la" -gt "$LOCK_TTL" ] && stale=", STALE"
      echo "$(basename "$l" .lock): $lo (${la}s$stale)"
    done
    [ "$found" -eq 1 ] || echo "No locks held."
    ;;
  log)
    msg="$ws"; who="${1:-${USER:-agent}}"; ws="."; need_ctx
    [ "$msg" != "." ] || { echo 'Usage: ctx log "<what happened>" [who]   (run in the workspace)'; exit 1; }
    br=""; has_git && br="$(git -C "$ws" branch --show-current 2>/dev/null || true)"
    printf '\n## %s - %s\n- Branch: %s\n- By: %s\n' "$(date +%Y-%m-%d)" "$msg" "${br:-n/a}" "$who" >> "$ctx/log.md"
    echo "Appended to log.md."
    ;;
  agents)
    target="$ws"; ws="."; ws="$(cd "$ws" && pwd)"; td="$ws/team-context"
    [ -d "$td" ] || { echo "No team-context/. Run: ctx team"; exit 1; }
    [ "$target" != "." ] || target="AGENTS.md"
    body="$(for f in "$td"/*.md; do
      [ "$(basename "$f")" = README.md ] && continue
      [ -f "$SRC/$(basename "$f")" ] && cmp -s "$f" "$SRC/$(basename "$f")" && continue
      awk '
        /<[^>][^>]+>/ { next }
        { lines[++n] = $0 }
        END { pb = 1; for (i = 1; i <= n; i++) { l = lines[i]
          if (l ~ /^#+ /) { j = i + 1; while (j <= n && lines[j] ~ /^[ \t]*$/) j++
            if (j > n || lines[j] ~ /^#+ /) continue
            sub(/^#+/, "&#", l) }
          if (l ~ /^[ \t]*$/) { if (pb) continue; pb = 1 } else pb = 0
          print l } }' "$f"; echo
    done)"
    [ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ] || { echo "team-context/ is still a template. Fill it in first."; exit 1; }
    bf="$(mktemp)"
    { echo '<!-- team-context:start -->'; echo '<!-- Generated by ctx agents from team-context/. Edit there, then re-run. -->'; echo '## Team rules'; printf '%s\n' "$body"; echo '<!-- team-context:end -->'; } > "$bf"
    tp="$ws/$target"
    if [ -f "$tp" ] && grep -q 'team-context:start' "$tp"; then
      awk -v bf="$bf" '/<!-- team-context:start -->/ { while ((getline line < bf) > 0) print line; skip = 1; next } /<!-- team-context:end -->/ { skip = 0; next } !skip' "$tp" > "$tp.new" && mv "$tp.new" "$tp"
    elif [ -f "$tp" ]; then { echo; cat "$bf"; } >> "$tp"
    else cp "$bf" "$tp"; fi
    rm -f "$bf"
    echo "Wrote team rules into $target. Review and commit it: unlike .context/, it is shared."
    ;;
  hooks)
    sub="$ws"; ws="${1:-.}"
    case "$sub" in
      git)
        ws="$(cd "$ws" && pwd)"
        hd="$(git -C "$ws" rev-parse --git-path hooks 2>/dev/null)" || { echo "Not a git repo."; exit 1; }
        case "$hd" in /*|[A-Za-z]:*) ;; *) hd="$ws/$hd" ;; esac
        mkdir -p "$hd"; hf="$hd/post-commit"
        if [ -f "$hf" ] && grep -q 'local-context:start' "$hf"; then echo "post-commit hook already installed."; exit 0; fi
        [ -f "$hf" ] || printf '#!/bin/sh\n' > "$hf"
        cat >> "$hf" <<'EOF'
# local-context:start
if command -v ctx >/dev/null 2>&1; then ctx snapshot . "after commit" >/dev/null 2>&1 || true
elif command -v ctx.cmd >/dev/null 2>&1; then ctx.cmd snapshot . "after commit" >/dev/null 2>&1 || true; fi
# local-context:end
EOF
        chmod +x "$hf"
        echo "Installed post-commit hook ($hf): saves a .context snapshot after each commit. Local only, never committed."
        ;;
      git-remove)
        ws="$(cd "$ws" && pwd)"
        hd="$(git -C "$ws" rev-parse --git-path hooks 2>/dev/null)" || { echo "Not a git repo."; exit 1; }
        case "$hd" in /*|[A-Za-z]:*) ;; *) hd="$ws/$hd" ;; esac
        hf="$hd/post-commit"; [ -f "$hf" ] || { echo "No post-commit hook."; exit 0; }
        awk '/# local-context:start/ { skip = 1; next } /# local-context:end/ { skip = 0; next } !skip' "$hf" > "$hf.new" && mv "$hf.new" "$hf"; chmod +x "$hf"
        if [ -z "$(grep -v '^#!' "$hf" | tr -d '[:space:]')" ]; then rm -f "$hf"; fi
        echo "Removed the local-context post-commit hook."
        ;;
      claude)
        cat <<'EOF'
Claude Code: make every session start with the context brief. Add this to .claude/settings.local.json (this project, not committed) or ~/.claude/settings.json (all projects), merging with any existing "hooks":

{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "ctx brief" } ] }
    ]
  }
}

Per the hooks docs, a SessionStart hook's plain-text stdout is added to Claude's context. Add "matcher": "startup" to the group to skip resume/clear/compact. There is no Stop hook here on purpose: plain stdout from Stop does not reach the model. Run ctx wrap yourself, or install the git hook: ctx hooks git
EOF
        ;;
      *) echo "Usage: ctx hooks <git|git-remove|claude> [workspace]" ;;
    esac
    ;;
  upgrade)
    need_ctx
    cp "$SRC/START_HERE.md" "$ctx/START_HERE.md"
    (cd "$SRC" && find . -type f) | while read -r rel; do
      if [ ! -e "$ctx/$rel" ]; then mkdir -p "$ctx/$(dirname "$rel")"; cp "$SRC/$rel" "$ctx/$rel"; echo "Added $rel"; fi
    done
    snapshot "ctx upgrade" || true
    echo "START_HERE.md refreshed; missing files added."
    ;;
  version) echo "ctx $(head -1 "$HOME_DIR/VERSION" 2>/dev/null || echo dev)" ;;
  update)
    [ -f "$HOME_DIR/repo.txt" ] || { echo "No repo.txt: installed from a clone? Use git pull there."; exit 1; }
    r="$(sed -n 1p "$HOME_DIR/repo.txt")"; b="$(sed -n 2p "$HOME_DIR/repo.txt")"
    ref=""; [ "$ws" = "." ] || ref="$ws"
    curl -fsSL "https://raw.githubusercontent.com/$r/${ref:-$b}/install.sh" | CTX_REPO="$r" CTX_BRANCH="$b" CTX_REF="$ref" sh
    ;;
  uninstall)
    expected="${CTX_HOME:-$HOME/.local-context}"
    [ "$HOME_DIR" = "$expected" ] || { echo "Refusing: this copy ($HOME_DIR) is not the installed one ($expected)."; exit 1; }
    if [ "${ws}" != "--yes" ] && [ "${ws}" != "-Yes" ]; then echo "Would remove $HOME_DIR and ${CTX_BIN:-$HOME/.local/bin}/ctx. Workspace .context folders are untouched. Re-run with --yes to confirm."; exit 0; fi
    rm -f "${CTX_BIN:-$HOME/.local/bin}/ctx"; rm -rf "$HOME_DIR"
    echo "ctx removed. Your workspace .context folders were not touched."
    ;;
  *)
    cat <<'EOF'
Usage: ctx <command> [path]
  init [path] [pointer-file ...]  create .context/, scan repo, hide from git
  status | brief | doctor | wrap | archive | scan | bootstrap | team
  snapshot [path] [message] | history | backup [path] [dest.tar.gz]
  restore <file> [rev]            restore a file from history (run in the workspace)
  lock <file> [owner] | unlock <file> [owner|--force] | locks    short leases for shared files
  log "<what happened>" [who]     append an entry to log.md safely
  agents [file]                   export team-context/ into a committable AGENTS.md block
  hooks <git|git-remove|claude>   install the git snapshot hook / print the Claude Code hook
  upgrade                         refresh the protocol, add missing templates
  update [ref]                    update ctx (latest release, or tag/branch/sha)
  uninstall --yes | version
EOF
    ;;
esac
