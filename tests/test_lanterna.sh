#!/usr/bin/env bash
# Tests /lanterna with stubbed Telegram and termux-torch. No phone needed.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
fails=0
ok()   { echo "ok   - $1"; }
bad()  { echo "FAIL - $1"; fails=$((fails+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

D=$T; SENT="$T/sent.log"; CALLS="$T/torch.log"; : > "$SENT"; : > "$CALLS"
send() { printf '%s\n' "$1" >> "$SENT"; }
printf '#!/bin/sh\necho "$@" >> "%s"\n[ "${FAKE_TORCH:-ok}" = ok ]\n' "$CALLS" > "$T/bin/termux-torch"
chmod +x "$T"/bin/*; PATH="$T/bin:$PATH"
eval "$(sed -n '/^cmd_lanterna()/,/^}/p' "$ROOT/tgbot/bot.sh")"

cmd_lanterna on
check "on: calls termux-torch on and confirms" '[ "$(cat "$CALLS")" = on ] && grep -q "Lanterna acesa" "$SENT"'
: > "$CALLS"; : > "$SENT"; cmd_lanterna OFF
check "OFF (any case): calls termux-torch off and confirms" '[ "$(cat "$CALLS")" = off ] && grep -q "Lanterna apagada" "$SENT"'
: > "$CALLS"; : > "$SENT"; cmd_lanterna ligar
check "portuguese word ligar works" '[ "$(cat "$CALLS")" = on ]'
: > "$CALLS"; : > "$SENT"; cmd_lanterna ""
check "no argument: shows usage, does not touch the torch" '[ ! -s "$CALLS" ] && grep -q "/lanterna on" "$SENT"'
: > "$CALLS"; : > "$SENT"; cmd_lanterna "; rm -rf /"
check "garbage argument is never passed to termux-torch" '[ ! -s "$CALLS" ] && grep -q "Use /lanterna" "$SENT"'
: > "$SENT"; FAKE_TORCH=fail cmd_lanterna on
check "failure is reported" 'grep -q "Não consegui mexer na lanterna" "$SENT"'
check "bot routes /lanterna and /luz" 'grep -q "/lanterna|/luz) cmd_lanterna" "$ROOT/tgbot/bot.sh"'
exit $fails
