#!/usr/bin/env sh
# Local-context scaffolder (POSIX). Harness-agnostic.
# Usage: ctx.sh init [path] [pointer-file ...] | status [path] | upgrade [path]
set -eu
self="$0"
while [ -h "$self" ]; do
  d="$(cd "$(dirname "$self")" && pwd)"; self="$(readlink "$self")"
  case "$self" in /*) ;; *) self="$d/$self" ;; esac
done
HOME_DIR="$(cd "$(dirname "$self")" && pwd)"
SRC="$HOME_DIR/templates"
BOOT="Read .context/START_HERE.md and follow it. It is this workspace's local project memory."
cmd="${1:-help}"; ws="${2:-.}"
[ $# -ge 2 ] && shift 2 || shift $#

exclude_file() {
  command -v git >/dev/null 2>&1 || return 1
  g="$(git -C "$ws" rev-parse --git-path info/exclude 2>/dev/null)" || return 1
  case "$g" in /*|[A-Za-z]:*) echo "$g";; *) echo "$ws/$g";; esac
}
add_exclude() {
  f="$(exclude_file)" || return 1
  mkdir -p "$(dirname "$f")"
  grep -qxF "$1" "$f" 2>/dev/null || echo "$1" >> "$f"
}

case "$cmd" in
  init)
    ws="$(cd "$ws" && pwd)"; ctx="$ws/.context"; mkdir -p "$ctx"; n=0
    (cd "$SRC" && find . -type f) | while read -r rel; do
      mkdir -p "$ctx/$(dirname "$rel")"
      [ -e "$ctx/$rel" ] || cp "$SRC/$rel" "$ctx/$rel"
    done
    cp "$SRC/START_HERE.md" "$ctx/START_HERE.md"
    if add_exclude ".context/"; then echo "Excluded via .git/info/exclude (local only)."; else echo "Not a git repo: nothing to exclude yet."; fi
    for p in "$@"; do
      pf="$ws/$p"
      if [ -f "$pf" ] && grep -q 'local-context:start' "$pf"; then continue; fi
      printf '\n<!-- local-context:start -->\n%s\n<!-- local-context:end -->\n' "$BOOT" >> "$pf"
      if ! git -C "$ws" ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then add_exclude "$p" || true
      else echo "warning: $p is tracked by git; the pointer block will show as a change."; fi
    done
    echo "Context ready: $ctx"
    echo; echo "Paste into ANY agent/harness (or its instruction file):"; echo "  $BOOT"
    ;;
  upgrade) cp "$SRC/START_HERE.md" "$ws/.context/START_HERE.md"; echo "START_HERE.md refreshed." ;;
  status)
    ctx="$ws/.context"; [ -d "$ctx" ] || { echo "No .context here. Run: ctx.sh init"; exit 0; }
    cat "$ctx/STATE.md"; echo; echo "--- Open checklist items ---"
    grep -rnE '^\s*- \[( |~|!)\]' "$ctx" --include='*.md' | grep -v '_template.md' | grep -v 'START_HERE.md' | grep -v '<' || true
    ;;
  update)
    [ -f "$HOME_DIR/repo.txt" ] || { echo "No repo.txt: installed from a clone? Use git pull there."; exit 1; }
    r="$(sed -n 1p "$HOME_DIR/repo.txt")"; b="$(sed -n 2p "$HOME_DIR/repo.txt")"
    curl -fsSL "https://raw.githubusercontent.com/$r/$b/install.sh" | CTX_REPO="$r" CTX_BRANCH="$b" sh
    ;;
  *) echo "Usage: ctx <init|status|upgrade|update> [path] [pointer-file ...]" ;;
esac
