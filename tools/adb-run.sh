#!/usr/bin/env bash
# Runs a script from this repo INSIDE Termux, from the PC, without root and without SSH.
#
#   tools/adb-run.sh install/dnsblock.sh
#
# How: serves the repo on 127.0.0.1:$PORT, `adb reverse` makes that port reachable from the phone
# as localhost:$PORT, wakes the screen, and types `curl -s http://localhost:$PORT/<script> | bash`
# into the Termux window that is open in the foreground. The phone must be awake and unlocked.
#
# Env: PORT (default 8765), TAP_X/TAP_Y (where to tap to focus the terminal, default 180 300),
#      WAIT (seconds to keep the server up, default 90).
# Tips from experience (docs/13-deploying-from-a-pc.md): typing is slow and lossy when the screen
# has just woken up; backslash-escaped spaces are typed literally; keep the typed command short.
set -euo pipefail
script="${1:?usage: tools/adb-run.sh <path-in-repo, e.g. install/dnsblock.sh>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-8765}"; TAP_X="${TAP_X:-180}"; TAP_Y="${TAP_Y:-300}"; WAIT="${WAIT:-90}"
[ -f "$root/$script" ] || { echo "no such file in repo: $script" >&2; exit 1; }
command -v adb >/dev/null || { echo "adb not found" >&2; exit 1; }
if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
  echo "port $PORT is already in use on this PC; pick another with PORT=..." >&2; exit 1
fi
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$root" >/dev/null 2>&1 &
srv=$!
cleanup() { kill "$srv" 2>/dev/null || true; adb reverse --remove "tcp:$PORT" >/dev/null 2>&1 || true; }
trap cleanup EXIT
sleep 1
adb reverse "tcp:$PORT" "tcp:$PORT" >/dev/null
adb shell am start -n com.termux/.app.TermuxActivity >/dev/null 2>&1 || true
adb shell input keyevent KEYCODE_WAKEUP; sleep 3
adb shell input tap "$TAP_X" "$TAP_Y"; sleep 1
adb shell "input text 'clear'"; adb shell input keyevent 66; sleep 1
adb shell "input text 'curl -s http://localhost:$PORT/$script | BASE=http://localhost:$PORT bash'"
adb shell input keyevent 66
echo "Command typed in Termux. Serving for up to ${WAIT}s (Ctrl+C when the phone shows it finished)..."
sleep "$WAIT"
