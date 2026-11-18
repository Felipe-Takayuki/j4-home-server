#!/usr/bin/env bash
# Tests /foto and /foto flash (the bridge to the FlashCam app) with stubbed Telegram, `am` and camera. No phone needed.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/tmp"
fails=0
ok()   { echo "ok   - $1"; }
bad()  { echo "FAIL - $1"; fails=$((fails+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

D=$T; OWNER_ID=1; SENT="$T/sent.log"; TGLOG="$T/tg.log"; : > "$SENT"; : > "$TGLOG"
log() { :; }
send() { printf '%s\n' "$1" >> "$SENT"; }
tg() {   # records the call; for sendPhoto also records the size of the file at that moment and the caption
  local m=$1 a; shift
  for a in "$@"; do
    case "$a" in photo=@*) echo "$m size=$(stat -c %s "${a#photo=@}")" >> "$TGLOG";; caption=*) echo "caption $a" >> "$TGLOG";; esac
  done
}
# fake `am`: plays the part of the FlashCam app, POSTing to the port/key it is given
cat > "$T/bin/am" <<'AM'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in --ei) port=$3; shift 2;; --es) key=$3; shift 2;; esac; shift; done
case "${FAKE_AM:-ok}" in
  fail)   echo "Error: Activity class {com.j4.flashcam/com.j4.flashcam.FlashActivity} does not exist."; exit 0;;
  silent) exit 0;;
  ok)     head -c 4000 /dev/urandom | curl -s -X POST -H 'X-Result: ok' --data-binary @- "http://127.0.0.1:$port/$key" >/dev/null;;
  erro)   printf 'sem permissão da câmera' | curl -s -X POST -H 'X-Result: erro' --data-binary @- "http://127.0.0.1:$port/$key" >/dev/null;;
  nokey)  printf 'x' | curl -s -X POST -H 'X-Result: ok' --data-binary @- "http://127.0.0.1:$port/errada" >/dev/null;;
esac
AM
printf '#!/bin/sh\nhead -c 3000 /dev/urandom > "$3"\n' > "$T/bin/termux-camera-photo"   # args: -c N file
chmod +x "$T"/bin/*; PATH="$T/bin:$PATH"
eval "$(sed -n '/^FOTO_FLASH_WAIT=/,/^SOUND_DIRS=/p' "$ROOT/tgbot/bot.sh" | sed '$d')"
FOTO_FLASH_WAIT=4

: > "$TGLOG"; FAKE_AM=ok cmd_foto "flash"
check "flash: the photo from the app is sent to Telegram" 'grep -q "^sendPhoto size=4000" "$TGLOG"'
check "flash: caption says rear camera with flash" 'grep -q "traseira com flash" "$TGLOG"'
check "flash: no photo is left on the phone" '[ -z "$(ls "$T/tmp" | grep -E "foto")" ]'

: > "$SENT"; : > "$TGLOG"; FAKE_AM=erro cmd_foto "flash"
check "flash: an error from the app is reported with its reason" 'grep -q "Não consegui tirar a foto com flash: sem permissão da câmera" "$SENT" && ! grep -q sendPhoto "$TGLOG"'

: > "$SENT"; FAKE_AM=fail cmd_foto "flash"
check "flash: app not installed gives a helpful message" 'grep -q "app de flash" "$SENT"'

: > "$SENT"; : > "$TGLOG"; FAKE_AM=nokey cmd_foto "flash"
check "flash: a POST with the wrong key is rejected (no photo sent)" 'grep -q "sem resposta do app" "$SENT" && ! grep -q sendPhoto "$TGLOG"'

: > "$SENT"; FAKE_AM=silent cmd_foto "flash"
check "flash: an app that never answers times out" 'grep -q "sem resposta do app" "$SENT"'

: > "$SENT"; : > "$TGLOG"; cmd_foto "frente flash"
check "flash is refused on the front camera" 'grep -q "frontal não tem flash" "$SENT" && ! grep -q sendPhoto "$TGLOG"'

: > "$TGLOG"; cmd_foto ""
check "plain /foto still uses the normal camera (rear)" 'grep -q "^sendPhoto size=3000" "$TGLOG" && grep -q "Câmera traseira ·" "$TGLOG"'
: > "$TGLOG"; cmd_foto "frente"
check "/foto frente still works (front)" 'grep -q "Câmera frontal ·" "$TGLOG"'
check "no photo or error file is left behind after any of the cases above" '[ -z "$(ls "$T/tmp" | grep -vx am.out)" ]'
exit $fails
