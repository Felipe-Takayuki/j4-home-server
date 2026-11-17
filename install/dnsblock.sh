# Installs the DNS ad blocker inside Termux. Run it from the PC with:
#     tools/adb-run.sh install/dnsblock.sh
# Needs: python (pkg install python), curl, and a working Tailscale with HTTPS certificates enabled.
set -e
BASE="${BASE:-http://localhost:8765}"
D="$HOME/.dnsblock"
mkdir -p "$D" "$HOME/.termux/boot"
for f in dnsblock.py run.sh; do curl -fsS "$BASE/dnsblock/$f" -o "$D/$f"; done
curl -fsS "$BASE/termux/boot/60-dnsblock" -o "$HOME/.termux/boot/60-dnsblock"
chmod 700 "$D"; chmod 755 "$D/run.sh" "$HOME/.termux/boot/60-dnsblock"
python3 -m py_compile "$D/dnsblock.py" && rm -rf "$D/__pycache__"
[ -f "$D/allow.txt" ]  || printf '# one domain per line: never blocked, even if it is in the list\n' > "$D/allow.txt"
[ -f "$D/custom.txt" ] || printf '# one domain per line: blocked in addition to the list\n' > "$D/custom.txt"
rm -f "$D/disabled"
if pgrep -f '[.]dnsblock/run[.]sh' >/dev/null; then pkill -f '[.]dnsblock/dnsblock[.]py'   # run.sh restarts it
else nohup sh "$D/run.sh" >/dev/null 2>&1 & fi
echo "dnsblock started; downloading the blocklist (first run)..."
for i in $(seq 1 40); do [ -s "$D/blocklist.txt" ] && break; sleep 3; done
sleep 3
tail -n 4 "$D/dnsblock.log"
# Termux cannot bind port 53, so the resolver listens on 127.0.0.1:5353 and Tailscale exposes it
# as DNS-over-TLS on the tailnet. Android "Private DNS" then points at <node>.<tailnet>.ts.net.
ts serve --bg --tls-terminated-tcp=853 tcp://localhost:5353 2>&1 | tail -n 3
ts serve status 2>&1 | head -12
echo
echo "Next: on each Android phone with Tailscale, set Settings > Private DNS > <this node's MagicDNS name>."
