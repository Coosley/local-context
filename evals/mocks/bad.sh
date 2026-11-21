#!/usr/bin/env sh
# Mock agent that behaves badly. For testing the eval runner only, not a real agent.
p="$(cat)"
case "$p" in
  *"Implement the plan"*) echo "// rewritten" > config.js ;;
  *"formats dates"*) echo "const moment = require('moment');" >> app.js ;;
  *"Where are we"*) echo "I need to scan the whole repo first." ;;
  *"Finish T3"*) f=.context/plans/2026-01-01-demo.md
     if [ -f "$f" ]; then sed -i.bak 's/T3 | IN PROGRESS 60%/T3 | COMPLETED 100%/' "$f"; rm -f "$f.bak"; fi
     echo "Done!" ;;
  *"auth test fails"*) sed -i.bak 's/!isAdmin(user)/false/' auth.js; rm -f auth.js.bak ;;
  *"--verbose"*) echo "// verbose flag" >> cli.js ;;
esac
