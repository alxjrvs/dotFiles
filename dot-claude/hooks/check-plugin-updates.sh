#!/bin/bash
# Check and update all installed Claude Code plugins
# Called via SessionStart hook

PLUGINS_FILE="$HOME/.claude/plugins/installed_plugins.json"
UPDATED=()

if [ ! -f "$PLUGINS_FILE" ]; then
  exit 0
fi

# Extract plugin names from installed_plugins.json
PLUGIN_NAMES=$(python3 -c "
import json, sys
with open('$PLUGINS_FILE') as f:
    data = json.load(f)
for name in data.get('plugins', {}):
    print(name)
" 2>/dev/null)

for plugin in $PLUGIN_NAMES; do
  output=$(claude plugin update "$plugin" 2>&1)
  if echo "$output" | grep -qi "updated\|new version"; then
    UPDATED+=("$plugin")
  fi
done

if [ ${#UPDATED[@]} -gt 0 ]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"Plugins updated: ${UPDATED[*]}. Restart to apply.\"}}"
fi

exit 0
