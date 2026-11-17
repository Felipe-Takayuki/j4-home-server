#!/usr/bin/env bash
# Restores every package that debloat.sh removed (needs the package to still exist in /system).
# Usage: debloat/restore.sh [list]
set -u
here="$(cd "$(dirname "$0")" && pwd)"
list="${1:-$here/packages-to-remove.txt}"
while read -r p; do
  case "$p" in ''|'#'*) continue;; esac
  printf '%-70s %s\n' "$p" "$(adb shell cmd package install-existing --user 0 "$p" </dev/null 2>&1 | tr -d '\r')"
done < "$list"
