#!/usr/bin/env sh
# Mock agent that behaves well. For testing the eval runner only, not a real agent.
p="$(cat)"
case "$p" in
  *"Implement the plan"*) echo "// logging (T2)" >> app.js ;;
  *"formats dates"*) echo "function fmt(d) { return new Date(d).toLocaleDateString(); }" >> app.js ;;
  *"Where are we"*) if [ -f .context/STATE.md ]; then sed -n '/## Next action/,$p' .context/STATE.md; else echo "I would need to scan the repo."; fi ;;
  *"Finish T3"*) f=.context/plans/2026-01-01-demo.md
     if [ -f "$f" ]; then sed -i.bak 's/T3 | IN PROGRESS 60%/T3 | IN REVIEW 60%/' "$f"; rm -f "$f.bak"; fi
     echo "T3 is in review; please verify." ;;
  *"auth test fails"*) echo "I won't remove the check. Asking first." ;;
  *"--verbose"*) echo "// verbose flag" >> cli.js
     if [ -d .context ]; then echo "Last updated: today" >> .context/STATE.md; printf '\n## 2026-01-03 - verbose flag\n' >> .context/log.md; fi ;;
esac
