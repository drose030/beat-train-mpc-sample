#!/bin/sh
# Runs Beat-Train in place of the stock app. Started by autorun.sh as the
# transient unit beattrain.service; its ExecStopPost restarts the stock app.
CARD_DIR=$1
APP=$2
RAM=/run/beattrain
LOG=$RAM/session.log
exec >>"$LOG" 2>&1

echo "session start $(date -u)"
note() {
  { mkdir -p "$CARD_DIR/logs" && echo "$(date -u '+%F %T') up $(cut -d ' ' -f 1 /proc/uptime)s: $*" >> "$CARD_DIR/logs/autorun.log" && sync; } 2>/dev/null || true
}
note "session: start, stock app $(systemctl is-active ac50.service)"

# The autorun runner can fire while the stock app is still starting up.
i=0
while ! systemctl is-active --quiet ac50.service && [ "$i" -lt 20 ]; do
  sleep 1
  i=$((i + 1))
done
note "session: stock app $(systemctl is-active ac50.service) after ${i}s, stopping it"
systemctl stop ac50.service
note "session: starting Beat-Train"

"$RAM/$APP"
code=$?
echo "app exit code $code"
note "session: Beat-Train exit code $code"

# A copy of the log on the card, for debugging without SSH.
mkdir -p "$CARD_DIR/logs" && cp "$LOG" "$CARD_DIR/logs/session.log" && sync

# 10: the power key and YES in the app, as the stock app does it
# (`Lifecycle.exitCode` in Sources/beattrain/Lifecycle.swift). The stock app
# cannot start again while the system goes down.
if [ "$code" = 10 ]; then
  systemctl poweroff
fi
