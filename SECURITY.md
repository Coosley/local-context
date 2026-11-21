# Security

## Reporting a vulnerability
Please report privately through GitHub's "Report a vulnerability" (Security tab of this repository). Don't open a public issue for security problems. You'll get a response as soon as practical.

## What to know about this tool
- `ctx` is plain shell and PowerShell. It makes no network calls except `install` and `ctx update`, which download this repository from GitHub.
- The installers edit your user PATH (Windows) or create a symlink in `~/.local/bin` (macOS/Linux). They do not require admin rights.
- Piping a script to a shell is a trust decision. Read `install.ps1` / `install.sh` first, or pin a specific release or commit: `CTX_REF=<tag-or-sha>`.
- `.context/` is local and never committed by `ctx`. `ctx doctor` scans it for secret-looking strings, but the scan is best effort. Never put secrets in it.
- `ctx uninstall` refuses to run on anything but the installed copy.
