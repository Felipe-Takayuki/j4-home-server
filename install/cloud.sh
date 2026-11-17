# Installs the "cloud" (dufs file server + custom UI) inside Termux. Run it from the PC with:
#     tools/adb-run.sh install/cloud.sh
# Idempotent: an existing ~/.dufs/config.yaml (and its password) is never overwritten.
set -e
BASE="${BASE:-http://localhost:8765}"
D="$HOME/.dufs"
command -v dufs >/dev/null || { echo "dufs not installed: run  pkg install dufs  first"; exit 1; }
mkdir -p "$D/assets" "$HOME/cloud" "$HOME/.termux/boot"; chmod 700 "$D"
curl -fsS "$BASE/ui/index.html" -o "$D/assets/index.html"
for f in status.sh status-loop.sh; do curl -fsS "$BASE/cloud/$f" -o "$D/$f"; done
for f in 30-cloud 40-status; do curl -fsS "$BASE/termux/boot/$f" -o "$HOME/.termux/boot/$f"; done
chmod 755 "$D/status.sh" "$D/status-loop.sh" "$HOME/.termux/boot/30-cloud" "$HOME/.termux/boot/40-status"
if [ ! -f "$D/config.yaml" ]; then
  pw=$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)
  curl -fsS "$BASE/cloud/config.example.yaml" | sed "s/CHANGE-ME/$pw/" > "$D/config.yaml"
  chmod 600 "$D/config.yaml"
  echo "=============================================================="
  echo " Cloud login (shown ONCE, only on this screen):"
  echo "   user: cloud     password: $pw"
  echo " It is stored in $D/config.yaml; change it there any time."
  echo "=============================================================="
fi
# dufs keeps the custom UI in memory: restart it so the new index.html is served
pkill dufs 2>/dev/null || true; sleep 1
sh "$HOME/.termux/boot/30-cloud"; sh "$HOME/.termux/boot/40-status"
sleep 2; pgrep dufs >/dev/null && echo "dufs running on 127.0.0.1:8080" || echo "dufs did not start: see $D/dufs.log"
echo "Expose it on the tailnet with:  ts serve --bg --https=443 http://127.0.0.1:8080"
