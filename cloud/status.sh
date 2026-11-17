#!/data/data/com.termux/files/usr/bin/sh
# Writes disk usage to ~/cloud/.nuvem-status.json; the UI reads it for the storage panel.
export PATH=/data/data/com.termux/files/usr/bin:$PATH
H=/data/data/com.termux/files/home
OUT=$H/cloud/.nuvem-status.json
set -- $(df -k $H | awk 'NR==2{print $2, $3, $4}')
total=$1; used=$2; avail=$3
cloud=$(du -sk $H/cloud 2>/dev/null | cut -f1)
printf '{"total":%s,"used":%s,"avail":%s,"cloud":%s,"updated":%s}\n' $((total*1024)) $((used*1024)) $((avail*1024)) $(( ${cloud:-0}*1024 )) $(date +%s) > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
