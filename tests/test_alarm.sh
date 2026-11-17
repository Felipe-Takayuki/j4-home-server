#!/usr/bin/env bash
# Tests the alarm-clock logic of tgbot/bot.sh with stubbed Telegram/Termux commands. No phone needed.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/snd"; touch "$T/snd/Rush.ogg" "$T/snd/Morning_Glory.ogg"
printf '#!/bin/sh\n' > "$T/bin/termux-volume"
printf '#!/bin/sh\necho "$@" >> %s/player.log\n' "$T" > "$T/bin/termux-media-player"
chmod +x "$T"/bin/*
fails=0
ok()   { echo "ok   - $1"; }
bad()  { echo "FAIL - $1"; fails=$((fails+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# load only the functions under test from bot.sh, in a subshell-free way
D=$T; PATH="$T/bin:$PATH"; SOUND_DIRS="$T/snd"; SENT="$T/sent.log"; : > "$SENT"
log() { :; }
send() { printf '%s\n---\n' "$1" >> "$SENT"; }
eval "$(sed -n '/^find_sound()/,/^}/p' "$ROOT/tgbot/bot.sh")"
eval "$(sed -n '/^# ---------- Despertador/,/^# ---------- Bloqueador de DNS/p' "$ROOT/tgbot/bot.sh" | sed '$d')"
last() { tail -n 3 "$SENT"; }

now=$(date +%H:%M)

cmd_despertador "06:45 semana rush"
check "creates a weekday alarm with a case-insensitive sound" 'grep -q "^1|06:45|weekdays|Rush|" "$ALARMS"'
cmd_despertador "7h diario"
check "accepts a bare 7h as 07:00 and daily mode" 'grep -q "^2|07:00|daily|Morning_Glory|" "$ALARMS"'
cmd_despertador "25:00"
check "rejects an invalid time" 'grep -q "Não entendi" "$SENT" && ! grep -q "25:00" "$ALARMS"'
cmd_despertador "5h40 fds"
check "accepts 5h40 and weekend mode" 'grep -q "^3|05:40|weekend|" "$ALARMS"'
cmd_despertador "08:00 somnenhum"
check "rejects an unknown sound" '[ "$(wc -l < "$ALARMS")" -eq 3 ]'
cmd_despertador "lista"
check "lists alarms" 'grep -q "1) 06:45" "$SENT"'
cmd_despertador "apagar 1"
check "deletes alarm 1" '! grep -q "^1|" "$ALARMS" && grep -q "^2|" "$ALARMS"'
cmd_despertador "apagar todos"
check "deletes all alarms" '[ ! -s "$ALARMS" ]'

# an alarm for the current minute is pushed to tomorrow (last fired = today)
cmd_despertador "$now"
check "an alarm for the current minute waits until tomorrow" 'grep -q "|$(date +%F)$" "$ALARMS"'

# firing: a one-shot alarm due this minute rings once and is removed
: > "$ALARMS"; printf '9|%s|once|Rush|\n' "$now" > "$ALARMS"
sed 's/sleep 15/sleep 1/' <<<"$(declare -f alarm_loop)" > "$T/loop.sh"; . "$T/loop.sh"
alarm_loop & lp=$!; sleep 3; kill $lp 2>/dev/null; wait $lp 2>/dev/null
check "a due one-shot alarm is announced" 'grep -q "Despertador $now" "$SENT"'
check "a due one-shot alarm is removed" '[ ! -s "$ALARMS" ]'
check "a due alarm plays the sound" 'grep -q "play .*Rush.ogg" "$T/player.log"'
stop_ring
exit $fails
