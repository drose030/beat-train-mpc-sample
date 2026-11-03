#!/bin/sh
# Builds the SD-card contents for the MPC Sample:
#
#   dist/card/autorun/          the autorun package
#   dist/card/BeatTrain/Songs/  the songs (only with SONGS_DIR)
#   dist/beattrain-card.zip     the same, for the virtual-mpc-sample lab
#   dist/beattrain-mpc-sample.zip  the release download: autorun/, an empty
#                               BeatTrain/Songs/ and LICENSE, never songs
#
# Copy everything in dist/card to the root of the card.
#
#   scripts/package-autorun.sh [product]       default: beattrain (or beattrain-hwtest)
#   SONGS_DIR=path/to/Songs scripts/package-autorun.sh
#   SONGS_CHARTS_ONLY=1 ...    copy only song.ini, charts and album art (a small lab card)
set -eu

PRODUCT=${1:-beattrain}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST=$ROOT/dist
CARD=$DIST/card
OUT=$CARD/autorun
ZIP=$DIST/beattrain-card.zip
RELEASE_ZIP=$DIST/beattrain-mpc-sample.zip
# Salt of the firmware's az01-script-runner (1.3.0.12), see virtual-mpc-sample
# docs/CUSTOM_FIRMWARE.md.
RUNNER_SALT=f7bed1c9-7e90-4731-9194-c996666b4331

case "$PRODUCT" in
  beattrain) MESSAGE="Start Beat-Train?" ;;
  beattrain-hwtest) MESSAGE="Start Beat-Train hardware test?" ;;
  *) echo "unknown product: $PRODUCT" >&2; exit 1 ;;
esac

BIN=$("$ROOT/scripts/build-linux.sh" "$PRODUCT")

rm -rf "$CARD" "$ZIP" "$RELEASE_ZIP"
mkdir -p "$OUT"
sed "s/__MESSAGE__/$MESSAGE/" "$ROOT/packaging/autorun/autorun.json" > "$OUT/autorun.json"
sed "s/^APP=.*/APP=$PRODUCT/" "$ROOT/packaging/autorun/autorun.sh" > "$OUT/autorun.sh"
cp "$ROOT/packaging/autorun/session.sh" "$ROOT"/packaging/sounds/*.mp3 "$ROOT"/packaging/images/*.ppm "$OUT/"
chmod 755 "$OUT/autorun.sh" "$OUT/session.sh"

# Strip debug info inside the container (aarch64 binutils).
cp "$BIN" "$OUT/$PRODUCT"
docker run --rm -v "$OUT":/out swift:6.4.2 strip "/out/$PRODUCT"
(cd "$OUT" && shasum -a 256 "$PRODUCT" > "$PRODUCT.sha256")

# autorun.check = sha256(autorun.json bytes + autorun.sh bytes + runner salt)
{ cat "$OUT/autorun.json" "$OUT/autorun.sh"; printf '%s' "$RUNNER_SALT"; } \
  | shasum -a 256 | cut -d ' ' -f 1 | tr -d '\n' > "$OUT/autorun.check"

if [ -n "${SONGS_DIR:-}" ]; then
  mkdir -p "$CARD/BeatTrain/Songs"
  if [ -n "${SONGS_CHARTS_ONLY:-}" ]; then
    (cd "$SONGS_DIR" && find . -type f \( -iname song.ini -o -iname 'notes.mid' -o -iname 'notes.midi' \
        -o -iname 'notes.chart' -o -iname 'album.*' \) -exec sh -c \
        'mkdir -p "$1/$(dirname "$0")" && cp "$0" "$1/$0"' {} "$CARD/BeatTrain/Songs" \;)
  else
    cp -R "$SONGS_DIR"/. "$CARD/BeatTrain/Songs/"
  fi
  find "$CARD" -name .DS_Store -delete
fi

(cd "$CARD" && zip -qr "$ZIP" .)

RELEASE=$(mktemp -d)
cp -R "$OUT" "$RELEASE/autorun"
mkdir -p "$RELEASE/BeatTrain/Songs"
cp "$ROOT/LICENSE" "$RELEASE/"
(cd "$RELEASE" && zip -qrX "$RELEASE_ZIP" autorun BeatTrain LICENSE)
rm -rf "$RELEASE"
du -sh "$CARD" | cut -f 1
echo "$ZIP"
