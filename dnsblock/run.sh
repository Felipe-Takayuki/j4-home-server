#!/data/data/com.termux/files/usr/bin/sh
# Mantém o bloqueador de DNS vivo: se cair, sobe de novo em 5 s.
D=/data/data/com.termux/files/home/.dnsblock
B=/data/data/com.termux/files/usr/bin
export PATH=$B
while [ -f "$D/dnsblock.py" ] && [ ! -f "$D/disabled" ]; do
  $B/python3 "$D/dnsblock.py" >> "$D/dnsblock.log" 2>&1
  [ "$(stat -c %s "$D/dnsblock.log" 2>/dev/null || echo 0)" -gt 100000 ] && tail -n 100 "$D/dnsblock.log" > "$D/dnsblock.log.tmp" && mv "$D/dnsblock.log.tmp" "$D/dnsblock.log"
  sleep 5
done
