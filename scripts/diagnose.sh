#!/usr/bin/env bash
# diagnose.sh — collect system info and compute the OBS render-lag percentage.
# Read-only: it changes nothing. Safe to run any time.
#
# Usage:  ./scripts/diagnose.sh
set -u

cyan() { printf '\033[1;36m%s\033[0m\n' "$1"; }

cyan "=== System ==="
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "OS            : ${PRETTY_NAME:-unknown}"
fi
echo "Kernel        : $(uname -r)"
echo "Session type  : ${XDG_SESSION_TYPE:-unknown}"
echo "Desktop       : ${XDG_CURRENT_DESKTOP:-unknown}"
if command -v glxinfo >/dev/null 2>&1; then
  echo "GL renderer   : $(glxinfo -B 2>/dev/null | awk -F': ' '/OpenGL renderer string/ {print $2; exit}')"
else
  echo "GL renderer   : (install mesa-utils to show glxinfo)"
fi

cyan "=== GNOME animations / blanking ==="
if command -v gsettings >/dev/null 2>&1; then
  echo "enable-animations : $(gsettings get org.gnome.desktop.interface enable-animations 2>/dev/null)"
  echo "idle-delay        : $(gsettings get org.gnome.desktop.session idle-delay 2>/dev/null)"
  echo "screensaver idle  : $(gsettings get org.gnome.desktop.screensaver idle-activation-enabled 2>/dev/null)"
else
  echo "(gsettings not found)"
fi

cyan "=== Hardware encoders ==="
if command -v vainfo >/dev/null 2>&1; then
  vainfo 2>/dev/null | grep -E 'Driver version|VAProfile' | head -n 20
  echo "(If no VAProfile appears, there is no working VAAPI encoder -> use x264.)"
else
  echo "(vainfo not installed. On a GPU-less VM, assume there is no VAAPI encoder.)"
fi

cyan "=== OBS logs ==="
LOGDIR="${HOME}/.config/obs-studio/logs"
if [ ! -d "$LOGDIR" ]; then
  echo "No OBS log directory at $LOGDIR — run OBS at least once."
  exit 0
fi

# Use a glob + mapfile so file names containing spaces are handled correctly
# (OBS log names look like "2026-10-12 17-23-08.txt").
shopt -s nullglob
logfiles=("$LOGDIR"/*.txt)
shopt -u nullglob

if [ "${#logfiles[@]}" -eq 0 ]; then
  echo "(no .txt logs found)"
  exit 0
fi

mapfile -t logs < <(ls -1t "${logfiles[@]}" | head -n 3)

for f in "${logs[@]}"; do
  echo
  echo "--- $(basename "$f") ---"
  grep -E "Number of lagged frames|Total frames output|Total drawn frames" "$f" | sed 's/^/  /' || true

  prof=$(grep -E "render_convert_texture|render_displays|video_thread_time|output_frame" "$f" || true)
  if [ -n "$prof" ]; then
    echo "  -- profiler --"
    echo "$prof" | sed 's/^/  /'
  fi

  line=$(grep -oE "lagged frames due to rendering lag/stalls: [0-9]+ \([0-9.]+%\)" "$f" | tail -n 1 || true)
  if [ -n "$line" ]; then
    pct=$(printf '%s' "$line" | grep -oE "\([0-9.]+%" | tr -d '(%')
    verdict=$(awk -v p="$pct" 'BEGIN{
      if (p+0 < 1)       print "OK (<1%)";
      else if (p+0 < 5)  print "BORDERLINE";
      else               print "BAD - apply the settings in README.md";
    }')
    echo "  => render lag: ${pct}%  [${verdict}]"
  fi
done

echo
cyan "Tip: for live numbers while recording, use scripts/obs-stat.py (OBS WebSocket)."
