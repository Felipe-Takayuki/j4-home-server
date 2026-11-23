# Installs the Telegram bot inside Termux. Run it from the PC with:
#     tools/adb-run.sh install/tgbot.sh
# Needs: pkg install jq curl termux-api (+ the Termux:API Android app with the CAMERA permission).
# The bot token is NOT handled here: create ~/.tgbot/config yourself (see docs/08-telegram-bot.md).
set -e
BASE="${BASE:-http://localhost:8765}"
D="$HOME/.tgbot"
mkdir -p "$D/tmp" "$HOME/.termux/boot"; chmod 700 "$D" "$D/tmp"
[ -f "$D/bot.sh" ] && cp "$D/bot.sh" "$D/bot.sh.bak"
for f in bot.sh run.sh; do curl -fsS "$BASE/tgbot/$f" -o "$D/$f.new"; done
bash -n "$D/bot.sh.new"
mv "$D/bot.sh.new" "$D/bot.sh"; mv "$D/run.sh.new" "$D/run.sh"
curl -fsS "$BASE/termux/boot/50-tgbot" -o "$HOME/.termux/boot/50-tgbot"
chmod 755 "$D/run.sh" "$HOME/.termux/boot/50-tgbot"
for c in jq curl termux-battery-status termux-camera-photo termux-torch termux-media-player; do
  command -v "$c" >/dev/null || echo "WARNING: '$c' not found (pkg install jq curl termux-api)"
done
if [ ! -f "$D/config" ]; then
  echo "No $D/config yet. Create it (chmod 600) with TOKEN and OWNER_ID, then run:  sh $HOME/.termux/boot/50-tgbot"
else
  pkill -f '[.]tgbot/bot[.]sh' 2>/dev/null || true     # run.sh restarts it with the new code
  pgrep -f '[.]tgbot/run[.]sh' >/dev/null || nohup sh "$D/run.sh" >/dev/null 2>&1 &
  sleep 8; tail -n 2 "$D/bot.log"
fi
