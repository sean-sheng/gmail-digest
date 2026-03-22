#!/usr/bin/env bash
# Wrapper script for gmail-digest cron job.
# Runs the Claude skill and sends a macOS notification when done.

set -euo pipefail

PROJECT_DIR="$HOME/development/gmail-digest"
CLAUDE_BIN="${CLAUDE_BIN:-$(which claude 2>/dev/null || echo "/usr/local/bin/claude")}"
DIGESTS_DIR="$PROJECT_DIR/digests"

# Run the digest skill
"$CLAUDE_BIN" -p "/gmail-digest"

# Find the most recent digest file for the notification body
LATEST=$(ls -t "$DIGESTS_DIR"/*.md 2>/dev/null | head -1)
if [[ -n "$LATEST" ]]; then
  summary=$(head -3 "$LATEST" | tail -1)
  osascript -e "display notification \"$summary\" with title \"Gmail Digest Ready\" sound name \"Glass\""
else
  osascript -e 'display notification "Digest completed but file not found" with title "Gmail Digest" sound name "Basso"'
fi
