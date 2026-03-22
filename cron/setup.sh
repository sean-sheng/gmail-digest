#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$HOME/development/gmail-digest"
CONFIG="$PROJECT_DIR/config.json"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
LOG_DIR="$PROJECT_DIR/cron/logs"
PLIST_MORNING="com.gmail-digest.morning"
PLIST_AFTERNOON="com.gmail-digest.afternoon"

CLAUDE_BIN="$(which claude 2>/dev/null || echo "/usr/local/bin/claude")"

DRY_RUN=false
UNINSTALL=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=true ;;
    --uninstall) UNINSTALL=true ;;
  esac
done

# Read schedule and timezone from config.json
parse_config() {
  local result
  result=$(python3 -c "
import json, sys
with open('$CONFIG') as f:
    c = json.load(f)
schedule = c.get('schedule', ['07:00', '13:00'])
timezone = c.get('timezone', 'America/Los_Angeles')
morning_h,  morning_m   = schedule[0].split(':')
afternoon_h, afternoon_m = schedule[1].split(':')
print(morning_h, morning_m, afternoon_h, afternoon_m, timezone)
")
  echo "$result"
}

generate_plist() {
  local label="$1"
  local hour="$2"
  local minute="$3"
  local tz="$4"

  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>

    <key>ProgramArguments</key>
    <array>
        <string>${PROJECT_DIR}/cron/run-digest.sh</string>
    </array>

    <key>WorkingDirectory</key>
    <string>${PROJECT_DIR}</string>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>${hour}</integer>
        <key>Minute</key>
        <integer>${minute}</integer>
    </dict>

    <key>EnvironmentVariables</key>
    <dict>
        <key>TZ</key>
        <string>${tz}</string>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$(dirname "$CLAUDE_BIN")</string>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>CLAUDE_BIN</key>
        <string>${CLAUDE_BIN}</string>
    </dict>

    <key>StandardOutPath</key>
    <string>${LOG_DIR}/${label}.log</string>

    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/${label}.err</string>

    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
PLIST
}

uninstall() {
  local uid
  uid=$(id -u)
  for label in "$PLIST_MORNING" "$PLIST_AFTERNOON"; do
    local plist_path="$LAUNCH_AGENTS/${label}.plist"
    if launchctl list "$label" &>/dev/null; then
      if launchctl bootout "gui/$uid/$label" 2>/dev/null; then
        echo "Unloaded: $label"
      elif launchctl unload "$plist_path" 2>/dev/null; then
        echo "Unloaded (fallback): $label"
      fi
    fi
    if [[ -f "$plist_path" ]]; then
      rm "$plist_path"
      echo "Removed: $plist_path"
    fi
  done
  echo "Uninstall complete."
  exit 0
}

main() {
  local config_vals
  config_vals=$(parse_config)
  read -r morning_h morning_m afternoon_h afternoon_m tz <<< "$config_vals"

  # Strip leading zeros so bash doesn't treat them as octal
  morning_h="${morning_h#0}"
  morning_m="${morning_m#0}"
  afternoon_h="${afternoon_h#0}"
  afternoon_m="${afternoon_m#0}"
  morning_h="${morning_h:-0}"
  morning_m="${morning_m:-0}"
  afternoon_h="${afternoon_h:-0}"
  afternoon_m="${afternoon_m:-0}"

  local plist_morning
  local plist_afternoon
  plist_morning=$(generate_plist "$PLIST_MORNING"  "$morning_h"  "$morning_m"  "$tz")
  plist_afternoon=$(generate_plist "$PLIST_AFTERNOON" "$afternoon_h" "$afternoon_m" "$tz")

  if $DRY_RUN; then
    echo "=== DRY RUN — plists will not be installed ==="
    echo ""
    echo "--- ${PLIST_MORNING}.plist ---"
    echo "$plist_morning"
    echo ""
    echo "--- ${PLIST_AFTERNOON}.plist ---"
    echo "$plist_afternoon"
    echo ""
    echo "Config read from: $CONFIG"
    printf "Morning run:   %02d:%02d %s\n" "$morning_h" "$morning_m" "$tz"
    printf "Afternoon run: %02d:%02d %s\n" "$afternoon_h" "$afternoon_m" "$tz"
    exit 0
  fi

  mkdir -p "$LOG_DIR"

  echo "$plist_morning"   > "$LAUNCH_AGENTS/${PLIST_MORNING}.plist"
  echo "$plist_afternoon" > "$LAUNCH_AGENTS/${PLIST_AFTERNOON}.plist"

  local uid
  uid=$(id -u)
  for label in "$PLIST_MORNING" "$PLIST_AFTERNOON"; do
    local plist_path="$LAUNCH_AGENTS/${label}.plist"
    # Unload first if already loaded
    if launchctl list "$label" &>/dev/null; then
      launchctl bootout "gui/$uid/$label" 2>/dev/null \
        || launchctl unload "$plist_path" 2>/dev/null \
        || true
    fi
    launchctl bootstrap "gui/$uid" "$plist_path" 2>/dev/null \
      || launchctl load "$plist_path"
    echo "Loaded: $label"
  done

  echo ""
  echo "Gmail digest launchd jobs installed."
  printf "Morning run:   %02d:%02d %s\n" "$morning_h" "$morning_m" "$tz"
  printf "Afternoon run: %02d:%02d %s\n" "$afternoon_h" "$afternoon_m" "$tz"
  echo "Logs: $LOG_DIR"
}

if $UNINSTALL; then
  uninstall
fi

main
