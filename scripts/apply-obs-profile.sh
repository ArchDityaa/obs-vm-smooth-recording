#!/usr/bin/env bash
# apply-obs-profile.sh — install the "Smooth30" OBS profile into the user's
# config. It creates a NEW profile; it never touches your scenes or recordings.
#
# Usage:  ./scripts/apply-obs-profile.sh
set -euo pipefail

PROFILE_NAME="Smooth30"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/config"
OBS_ROOT="${HOME}/.config/obs-studio"
DST="$OBS_ROOT/basic/profiles/${PROFILE_NAME}"
GLOBAL="$OBS_ROOT/global.ini"

if [ ! -d "$OBS_ROOT" ]; then
  echo "OBS config not found at: $OBS_ROOT"
  echo "Open OBS Studio at least once, then run this script again."
  exit 1
fi

if pgrep -x obs >/dev/null 2>&1; then
  echo "OBS Studio looks like it is running. Please close it first."
  exit 1
fi

# Back up an existing profile directory, if any.
if [ -d "$DST" ]; then
  backup="${DST}.bak.$(date +%Y%m%d-%H%M%S)"
  mv "$DST" "$backup"
  echo "Existing profile backed up to: $backup"
fi

mkdir -p "$DST"
# basic.ini does not expand $HOME, so substitute the real path.
sed "s|__HOME__|${HOME}|g" "$SRC/basic.ini" > "$DST/basic.ini"
cp "$SRC/recordEncoder.json" "$DST/recordEncoder.json"
echo "Installed profile files into: $DST"

# Best-effort: make the new profile the active one.
if [ -f "$GLOBAL" ]; then
  cp "$GLOBAL" "${GLOBAL}.bak"
  if grep -q '^Profile=' "$GLOBAL"; then
    sed -i "s|^Profile=.*|Profile=${PROFILE_NAME}|" "$GLOBAL"
    if grep -q '^ProfileDir=' "$GLOBAL"; then
      sed -i "s|^ProfileDir=.*|ProfileDir=${PROFILE_NAME}|" "$GLOBAL"
    fi
    echo "Set '${PROFILE_NAME}' as the active profile (global.ini backup: ${GLOBAL}.bak)."
  else
    echo "Could not find 'Profile=' in global.ini; select '${PROFILE_NAME}' manually in OBS."
  fi
fi

cat <<EOF

Done.

Next steps in OBS Studio:
  1. Select the '${PROFILE_NAME}' profile (Profile menu) if not already active.
  2. Add the capture source:
       Sources -> +  ->  Screen Capture (PipeWire)  -> pick your monitor.
  3. Add audio sources (Desktop Audio, Mic/Aux) if they are missing.
  4. View -> uncheck "Preview" (saves ~10 ms/frame).
  4. Record a short test, then run: scripts/diagnose.sh

The optional scene collection at config/scene-template.json can be copied to
~/.config/obs-studio/basic/scenes/Desktop.json if you want the sources set up
for you (select it from Scene Collection menu afterwards).
EOF
