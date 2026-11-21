#!/usr/bin/env sh
# Installs/updates local-context globally (macOS/Linux). No git required.
#   curl -fsSL https://raw.githubusercontent.com/Coosley/local-context/main/install.sh | sh
# Override: CTX_REPO=owner/name CTX_BRANCH=main CTX_HOME=~/.local-context CTX_BIN=~/.local/bin
set -eu
REPO="${CTX_REPO:-Coosley/local-context}"
BRANCH="${CTX_BRANCH:-main}"
DEST="${CTX_HOME:-$HOME/.local-context}"
BIN="${CTX_BIN:-$HOME/.local/bin}"

mkdir -p "$DEST" "$BIN"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$tmp" --strip-components=1
cp -R "$tmp"/. "$DEST"/
printf '%s\n%s\n' "$REPO" "$BRANCH" > "$DEST/repo.txt"
chmod +x "$DEST/ctx.sh"
ln -sf "$DEST/ctx.sh" "$BIN/ctx"

echo "Installed local-context to $DEST (command: $BIN/ctx)"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Add to your shell profile:  export PATH=\"$BIN:\$PATH\"" ;; esac
echo "Next: cd into any workspace and run:  ctx init"
