#!/usr/bin/env bash
# Runs every offline check. Used by `make test` and by CI.
set -u
cd "$(dirname "$0")/.."
rc=0
echo "== shell syntax"; for f in tgbot/*.sh dnsblock/*.sh install/*.sh tools/*.sh debloat/*.sh cloud/*.sh termux/boot/* termux/bin/* tests/*.sh; do bash -n "$f" || { echo "syntax error: $f"; rc=1; }; done
echo "== python syntax"; python3 -m py_compile dnsblock/dnsblock.py tools/dot-query.py || rc=1
find . -name __pycache__ -type d -prune -exec rm -rf {} +
echo "== dnsblock unit tests"; python3 -m unittest -v tests/test_dnsblock.py || rc=1
echo "== alarm tests"; bash tests/test_alarm.sh || rc=1
echo "== reminder tests"; bash tests/test_reminders.sh || rc=1
find . -name __pycache__ -type d -prune -exec rm -rf {} +
[ $rc = 0 ] && echo "ALL OK" || echo "FAILED"
exit $rc
