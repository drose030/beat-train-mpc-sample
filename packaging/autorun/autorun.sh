#!/bin/sh
# Starts Beat-Train from the SD card. Only /run (RAM) is changed: after a
# power-off the MPC Sample is stock again. The stock app comes back as soon as
# Beat-Train exits or crashes (ExecStopPost of the transient unit).
set -eu

D=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RAM=/run/beattrain
UNIT=beattrain
APP=beattrain-hwtest

[ "$(id -u)" = 0 ] || exit 1
SYSTEMCTL=$(command -v systemctl) || exit 1
command -v systemd-run >/dev/null 2>&1 || exit 1

# A line in logs/autorun.log on the card, written through at once: it survives a
# hang or a hard power-off, unlike the session log in RAM.
note() {
  { mkdir -p "$D/logs" && echo "$(date -u '+%F %T') up $(cut -d ' ' -f 1 /proc/uptime)s: $*" >> "$D/logs/autorun.log" && sync; } 2>/dev/null || true
}
# Only the last 200 lines (about 30 starts) are kept.
if [ -f "$D/logs/autorun.log" ] && [ "$(wc -l < "$D/logs/autorun.log")" -gt 200 ]; then
  { tail -n 200 "$D/logs/autorun.log" > "$D/logs/autorun.log.new" && mv "$D/logs/autorun.log.new" "$D/logs/autorun.log"; } 2>/dev/null || true
fi
note "autorun.sh: stock app $("$SYSTEMCTL" is-active ac50.service 2>/dev/null || true)"
if "$SYSTEMCTL" is-active --quiet "$UNIT.service"; then
  note "autorun.sh: already running"
  exit 0
fi

mkdir -p "$RAM"
cp "$D/$APP" "$D/session.sh" "$RAM/"
chmod 755 "$RAM/$APP" "$RAM/session.sh"
for asset in "$D"/*.mp3 "$D"/*.ppm; do
  if [ -f "$asset" ]; then cp "$asset" "$RAM/"; fi
done

# Refuse to run a damaged copy.
if command -v sha256sum >/dev/null 2>&1; then
  expected=$(cut -d ' ' -f 1 "$D/$APP.sha256")
  actual=$(sha256sum "$RAM/$APP" | cut -d ' ' -f 1)
  if [ "$expected" != "$actual" ]; then
    echo "checksum mismatch: $actual" > "$RAM/error.log"
    note "autorun.sh: checksum mismatch"
    exit 1
  fi
fi

# A unit left over from a failed or killed session would block the name.
"$SYSTEMCTL" reset-failed "$UNIT.service" 2>/dev/null || true

# --no-block in ExecStopPost: a blocking start would wait for this unit's own stop
# job (ordering After=ac50.service) and deadlock until the stop timeout.
systemd-run --no-block --unit="$UNIT" \
  --property=After=ac50.service \
  --property="ExecStopPost=$SYSTEMCTL start --no-block ac50.service" \
  "$RAM/session.sh" "$D" "$APP"
note "autorun.sh: session queued"
