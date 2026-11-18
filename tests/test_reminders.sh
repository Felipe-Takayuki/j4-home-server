#!/usr/bin/env bash
# Tests the text-reminder logic (/lembrar) of tgbot/bot.sh with stubbed Telegram. No phone needed.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/snd"; touch "$T/snd/Ding_Dong.ogg" "$T/snd/Morning_Glory.ogg"
printf '#!/bin/sh\n' > "$T/bin/termux-volume"
printf '#!/bin/sh\necho "$@" >> %s/player.log\n' "$T" > "$T/bin/termux-media-player"
chmod +x "$T"/bin/*; PATH="$T/bin:$PATH"; SOUND_DIRS="$T/snd"
fails=0
ok()   { echo "ok   - $1"; }
bad()  { echo "FAIL - $1"; fails=$((fails+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

D=$T; SENT="$T/sent.log"; : > "$SENT"; SEND_FAILS=0
log() { :; }
send() { printf '%s\n---\n' "$1" >> "$SENT"; }
send_ok() { [ "$SEND_FAILS" = 1 ] && return 1; send "$1"; }
eval "$(sed -n '/^find_sound()/,/^}/p' "$ROOT/tgbot/bot.sh")"
eval "$(sed -n '/^# ---------- Despertador/,/^# ---------- Bloqueador de DNS/p' "$ROOT/tgbot/bot.sh" | sed '$d')"

now_s=$(date +%s)
line() { sed -n "${1}p" "$REMINDERS"; }

# relative times
cmd_lembrar "em 30min tirar a roupa"
t1=$(cut -d'|' -f2 "$REMINDERS" | sed -n 1p)
check "em 30min is ~30 minutes ahead" '[ $((t1 - now_s)) -ge 1790 ] && [ $((t1 - now_s)) -le 1815 ]'
check "keeps the text" 'grep -q "|once||tirar a roupa$" "$REMINDERS"'
cmd_lembrar "em 1h30 ligar pro João"
t2=$(cut -d'|' -f2 "$REMINDERS" | sed -n 2p)
check "em 1h30 is ~90 minutes ahead" '[ $((t2 - now_s)) -ge 5390 ] && [ $((t2 - now_s)) -le 5415 ]'
cmd_lembrar "em 2d renovar"
t3=$(cut -d'|' -f2 "$REMINDERS" | sed -n 3p)
check "em 2d is ~2 days ahead" '[ $((t3 - now_s)) -ge 172700 ] && [ $((t3 - now_s)) -le 172900 ]'

# tomorrow at a time, and date defaults
cmd_lembrar "amanhã 9h pagar a luz"
t4=$(cut -d'|' -f2 "$REMINDERS" | sed -n 4p)
check "amanhã 9h is tomorrow 09:00" '[ "$(date -d "@$t4" "+%F %H:%M")" = "$(date -d tomorrow +%F) 09:00" ]'
cmd_lembrar "amanha 7h30 acordar o João"
t5=$(cut -d'|' -f2 "$REMINDERS" | sed -n 5p)
check "7h30 parsed" '[ "$(date -d "@$t5" +%H:%M)" = "07:30" ]'
cmd_lembrar "amanhã comprar pão"
t6=$(cut -d'|' -f2 "$REMINDERS" | sed -n 6p)
check "a date with no time means 09:00" '[ "$(date -d "@$t6" +%H:%M)" = "09:00" ]'

# a bare time: today if still ahead, else tomorrow
cmd_lembrar "23:59 dormir"
t7=$(cut -d'|' -f2 "$REMINDERS" | sed -n 7p)
check "23:59 is today (or tomorrow if it is 23:59 right now)" '[ "$t7" -gt "$now_s" ] && [ $((t7 - now_s)) -le 86400 ]'
cmd_lembrar "00:00 virou o dia"
t8=$(cut -d'|' -f2 "$REMINDERS" | sed -n 8p)
check "a time that already passed today goes to tomorrow" '[ "$t8" -gt "$now_s" ] && [ "$(date -d "@$t8" +%F)" = "$(date -d tomorrow +%F)" ]'

# explicit dates
y=$(date +%Y)
cmd_lembrar "25/12 18h comprar presente"
t9=$(cut -d'|' -f2 "$REMINDERS" | sed -n 9p)
check "dd/mm resolves to a future date" '[ "$t9" -gt "$now_s" ] && [ "$(date -d "@$t9" +%d/%m\ %H:%M)" = "25/12 18:00" ]'
cmd_lembrar "31/02 absurdo"
check "an impossible date is rejected" 'grep -q "Essa data não existe" "$SENT" && ! grep -q "absurdo" "$REMINDERS"'
cmd_lembrar "01/01/2099 9h futuro distante"
check "dd/mm/yyyy works" 'grep -q "futuro distante" "$REMINDERS"'
cmd_lembrar "01/01/2001 9h passado"
check "a past date is rejected" 'grep -q "já passou" "$SENT" && ! grep -q "passado" "$REMINDERS"'
cmd_lembrar "sexta 9h reunião"
tw=$(cut -d'|' -f2 "$REMINDERS" | tail -1)
check "a weekday name is the next such day" '[ "$(date -d "@$tw" +%u)" = 5 ] && [ "$tw" -gt "$now_s" ]'

# recurring
cmd_lembrar "diario 8h tomar remédio"
check "daily reminder stored with time" 'grep -q "^[0-9]*|08:00|daily|.*|tomar remédio$" "$REMINDERS"'
cmd_lembrar "todo dia 7h alongar"
check "'todo dia' also means daily" 'grep -q "|07:00|daily|.*|alongar$" "$REMINDERS"'
cmd_lembrar "semana 8h30 stand-up"
check "weekday reminder" 'grep -q "|08:30|weekdays|.*|stand-up$" "$REMINDERS"'
cmd_lembrar "fds 10h feira"
check "weekend reminder" 'grep -q "|10:00|weekend|.*|feira$" "$REMINDERS"'
cmd_lembrar "diario remédio"
check "recurring without a time is rejected" 'grep -q "Falta o horário" "$SENT" && ! grep -q "|remédio$" "$REMINDERS"'

# text with pipes and numbers; errors
cmd_lembrar "em 10min a|b|c e 9 ovos"
check "text keeps pipes and a leading-number word is text" 'grep -q "|once||a|b|c e 9 ovos$" "$REMINDERS"'
n=$(wc -l < "$REMINDERS")
cmd_lembrar "amanhã 9h"
check "a reminder without text is rejected" '[ "$(wc -l < "$REMINDERS")" -eq "$n" ] && grep -q "Faltou o texto" "$SENT"'
cmd_lembrar "só um texto sem quando"
check "no time or date is rejected" 'grep -q "Faltou quando" "$SENT" && ! grep -q "sem quando" "$REMINDERS"'
cmd_lembrar "em xyz algo"
check "a bad duration is rejected" 'grep -q "Não entendi a duração" "$SENT"'

# list and delete
cmd_lembrar "lista"
check "lists reminders" 'grep -q "1) .* · tirar a roupa" "$SENT"'
cmd_lembrar "apagar 1"
check "deletes reminder 1" '! grep -q "^1|" "$REMINDERS" && grep -q "^2|" "$REMINDERS"'
cmd_lembrar "apagar todos"
check "deletes all reminders" '[ ! -s "$REMINDERS" ]'

# firing
: > "$SENT"
printf '1|%s|once||vencido há pouco\n2|%s|once||no futuro\n3|00:00|daily||diario passado\n' "$((now_s - 5))" "$((now_s + 3600))" > "$REMINDERS"
sed 's/sleep 15/sleep 1/' <<<"$(declare -f reminder_loop)" > "$T/loop.sh"; . "$T/loop.sh"
reminder_loop & lp=$!; sleep 3; kill $lp 2>/dev/null; wait $lp 2>/dev/null
check "a due one-shot reminder is sent" 'grep -q "🔔 Lembrete: vencido há pouco" "$SENT"'
check "a due one-shot reminder is removed" '! grep -q "vencido" "$REMINDERS"'
check "a future reminder stays and is not sent" 'grep -q "no futuro" "$REMINDERS" && ! grep -q "Lembrete: no futuro" "$SENT"'
check "a daily reminder fires once and is kept with today as last" 'grep -q "^3|00:00|daily|$(date +%F)|diario passado$" "$REMINDERS" && [ "$(grep -c "diario passado" "$SENT")" -eq 1 ]'

# late delivery is flagged; a failed send keeps the reminder
: > "$SENT"; printf '4|%s|once||atrasado\n' "$((now_s - 4000))" > "$REMINDERS"
reminder_loop & lp=$!; sleep 3; kill $lp 2>/dev/null; wait $lp 2>/dev/null
check "a late reminder says it was late" 'grep -q "era para" "$SENT" && grep -q "atrasado" "$SENT"'
: > "$SENT"; printf '5|%s|once||sem rede\n' "$((now_s - 5))" > "$REMINDERS"; SEND_FAILS=1
reminder_loop & lp=$!; sleep 3; kill $lp 2>/dev/null; wait $lp 2>/dev/null
check "a failed send keeps the reminder for the next round" 'grep -q "sem rede" "$REMINDERS"'

# the reminder beep: plays the short sound, stops by itself, never interrupts an alarm, /parar cuts it
REMINDER_BEEP_SECS=2; : > "$T/player.log"; rm -f "$D/ring.pid"
beep_reminder; sleep 4
check "the beep plays the reminder sound" 'grep -q "play .*Ding_Dong.ogg" "$T/player.log"'
check "the beep stops by itself and frees the marker" '[ "$(tail -n1 "$T/player.log")" = stop ] && [ ! -e "$D/ring.pid" ]'
: > "$T/player.log"; : > "$D/ring.pid"; beep_reminder; sleep 1
check "the beep does not interrupt a ringing alarm" '! grep -q play "$T/player.log"'
rm -f "$D/ring.pid"; : > "$T/player.log"; REMINDER_BEEP_SECS=30; beep_reminder; sleep 1; stop_ring; sleep 1
check "/parar (stop_ring) cuts the beep" '[ ! -e "$D/ring.pid" ] && [ "$(tail -n1 "$T/player.log")" = stop ]'
: > "$SENT"; : > "$T/player.log"; REMINDER_BEEP_SECS=2; SEND_FAILS=0; printf '7|%s|once||com toque\n' "$((now_s - 5))" > "$REMINDERS"
reminder_loop & lp=$!; sleep 3; kill $lp 2>/dev/null; wait $lp 2>/dev/null
check "a due reminder sends the message and rings" 'grep -q "Lembrete: com toque" "$SENT" && grep -q "play .*Ding_Dong" "$T/player.log"'
exit $fails
