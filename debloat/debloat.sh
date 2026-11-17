#!/usr/bin/env bash
# Removes packages for user 0 (reversible with restore.sh; nothing is deleted from /system).
# Usage: debloat/debloat.sh [--dry-run] [list]      (default list: debloat/packages-to-remove.txt)
# READ docs/02-debloat.md FIRST: the default list is aggressive and meant for a headless server.
set -u
dry=0; [ "${1:-}" = "--dry-run" ] && { dry=1; shift; }
here="$(cd "$(dirname "$0")" && pwd)"
list="${1:-$here/packages-to-remove.txt}"
command -v adb >/dev/null || { echo "adb not found" >&2; exit 1; }
log="$here/debloat.log"; : > "$log"
while read -r p; do
  case "$p" in ''|'#'*) continue;; esac
  if [ "$dry" = 1 ]; then out="(dry run)"
  else out=$(adb shell pm uninstall --user 0 "$p" </dev/null 2>&1 | tr -d '\r'); fi
  printf '%-70s %s\n' "$p" "$out"
done < "$list" | tee "$log"
echo "Done. Wait ~30 s before rebooting, otherwise Android may lose the change."
