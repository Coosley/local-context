#!/usr/bin/env sh
# Installs/updates ctx globally (macOS/Linux). No git required.
#   curl -fsSL https://raw.githubusercontent.com/Coosley/local-context/main/install.sh | sh
# Installs the latest tagged release if one exists, otherwise the main branch.
# Pin anything: CTX_REF=v0.2.0 (a tag, branch or full commit SHA)
# Other overrides: CTX_REPO=owner/name CTX_BRANCH=main CTX_HOME=~/.local-context CTX_BIN=~/.local/bin
set -eu
REPO="${CTX_REPO:-Coosley/local-context}"
BRANCH="${CTX_BRANCH:-main}"
DEST="${CTX_HOME:-$HOME/.local-context}"
BIN="${CTX_BIN:-$HOME/.local/bin}"
REF="${CTX_REF:-}"
if [ -z "$REF" ]; then
  REF="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)"
fi
[ -n "$REF" ] || REF="$BRANCH"
old="$(head -1 "$DEST/VERSION" 2>/dev/null || true)"
URL="https://github.com/$REPO/archive/$REF.tar.gz"
echo "Source: $URL"

mkdir -p "$DEST" "$BIN"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$URL" | tar -xz -C "$tmp" --strip-components=1
cp -R "$tmp"/. "$DEST"/
printf '%s\n%s\n' "$REPO" "$BRANCH" > "$DEST/repo.txt"
chmod +x "$DEST/ctx.sh"
ln -sf "$DEST/ctx.sh" "$BIN/ctx"

new="$(head -1 "$DEST/VERSION" 2>/dev/null || echo dev)"
if [ -n "$old" ] && [ "$old" != "$new" ]; then echo "Updated ctx $old -> $new ($REF) in $DEST"; else echo "Installed ctx $new ($REF) in $DEST (command: $BIN/ctx)"; fi
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Add to your shell profile:  export PATH=\"$BIN:\$PATH\"" ;; esac
echo "Next: cd into any workspace and run:  ctx init"
