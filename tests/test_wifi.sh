#!/usr/bin/env bash
# Tests the Wi-Fi watchdog step with stubbed ping, Telegram and termux-wifi-enable. No phone needed.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
fails=0
ok()   { echo "ok   - $1"; }
bad()  { echo "FAIL - $1"; fails=$((fails+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

D=$T; SENT="$T/sent.log"; CALLS="$T/wifi.log"; : > "$SENT"; : > "$CALLS"
send() { printf '%s\n' "$1" >> "$SENT"; }
log() { :; }
sleep() { :; }
printf '#!/bin/sh\n[ -f "%s/net_up" ]\n' "$T" > "$T/bin/ping"
printf '#!/bin/sh\necho "$@" >> "%s"\n' "$CALLS" > "$T/bin/termux-wifi-enable"
chmod +x "$T"/bin/*; PATH="$T/bin:$PATH"
eval "$(sed -n '/^net_ok()/p;/^wifi_step()/,/^}/p' "$ROOT/tgbot/bot.sh")"

WFAILS=0 WFIXED=0 WLAST=0
touch "$T/net_up"; wifi_step 1000
check "internet ok: nothing happens" '[ ! -s "$CALLS" ] && [ ! -s "$SENT" ] && [ $WFAILS = 0 ]'
rm "$T/net_up"; wifi_step 1030; wifi_step 1060
check "2 failures: still waiting" '[ ! -s "$CALLS" ] && [ $WFAILS = 2 ]'
wifi_step 1090
check "3rd failure: Wi-Fi toggled off then on" '[ "$(cat "$CALLS")" = "$(printf "false\ntrue")" ]'
: > "$CALLS"; wifi_step 1120; wifi_step 1150
check "cooldown: no second toggle within 10 min" '[ ! -s "$CALLS" ]'
wifi_step 1700
check "after 10 min still down: toggles again" '[ -s "$CALLS" ]'
touch "$T/net_up"; wifi_step 1730
check "back online after a fix: tells the owner once" '[ "$(grep -c "reiniciei o Wi-Fi" "$SENT")" = 1 ] && [ $WFIXED = 0 ]'
wifi_step 1760
check "no repeated message" '[ "$(grep -c "reiniciei o Wi-Fi" "$SENT")" = 1 ]'
check "watchdog is started and stopped by the bot" 'grep -q "^wifi_watch &" "$ROOT/tgbot/bot.sh" && grep -q "WIFIW_PID 2>/dev/null" "$ROOT/tgbot/bot.sh"'
exit $fails
