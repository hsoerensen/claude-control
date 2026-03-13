#!/usr/bin/env bash
set -euo pipefail

# Wrapper for claude remote-control that tries worktree mode first,
# falling back to single mode if the feature gate is not enabled.

stderr_file="$(mktemp)"
trap 'rm -f "$stderr_file"' EXIT

# Try worktree mode
set +e
"$CLAUDE_BIN" remote-control \
    --spawn worktree \
    --capacity "$CAPACITY" \
    --name "$SESSION_NAME" \
    --no-create-session-in-dir \
    2>"$stderr_file"
exit_code=$?
set -e

# Success — worktree mode worked
if [[ "$exit_code" -eq 0 ]]; then
    exit 0
fi

# Check if worktree mode was gated
if grep -q "not yet enabled" "$stderr_file"; then
    echo "Worktree mode not available, starting in single mode" >&2
    exec "$CLAUDE_BIN" remote-control --name "$SESSION_NAME"
fi

# Some other error — print captured stderr and exit with original code
cat "$stderr_file" >&2
exit "$exit_code"
