#!/usr/bin/env bash
set -uo pipefail
LOGDIR="$HOME/.claude/state/subagent-statusline-probe"
mkdir -p "$LOGDIR"
TS=$(date +%s%N 2> /dev/null || python3 -c "import time; print(int(time.time()*1e9))")
INPUT=$(cat)
echo "$INPUT" > "$LOGDIR/in-$TS.json"

# Trial 3: structured guess at schema using field names extracted from
# binary strings (tokenText, queuedText, queuedCount, elapsed, state).
# Echo the first task's id from the input so we can match against it.
OUTPUT=$(python3 -c "
import json, sys, os
inp = json.loads(open('$LOGDIR/in-$TS.json').read())
tasks = inp.get('tasks', [])
out_tasks = []
for t in tasks:
    out_tasks.append({
        'id': t.get('id', ''),
        'state': 'success',
        'tokenText': 'PROBE_TT',
        'queuedText': 'PROBE_QT',
        'queuedCount': 7,
        'elapsed': 'PROBE_ELAPSED',
    })
print(json.dumps({'tasks': out_tasks}))
")

printf '%s\n' "$OUTPUT" | tee "$LOGDIR/out-$TS.json"
