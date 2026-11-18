#!/data/data/com.termux/files/usr/bin/bash
# Bot do Telegram do servidor J4 (roda no Termux).
# Config: ~/.tgbot/config com TOKEN e OWNER_ID. Só o OWNER_ID é atendido.
# Comandos: /status /foto [frente] /tocar [nome|lista] /despertador /lembrar /dns /parar /ajuda
# Teste sem Telegram: bash bot.sh --status
export PATH=/data/data/com.termux/files/usr/bin:$PATH
H=/data/data/com.termux/files/home
D=$H/.tgbot
mkdir -p "$D/tmp"; chmod 700 "$D" "$D/tmp"
rm -f "$D"/tmp/foto.jpg "$D"/tmp/foto.jpg.err   # fotos nunca ficam guardadas: limpa qualquer sobra de uma queda no meio do envio

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$D/bot.log"; }

human() { awk -v b="$1" 'BEGIN{ if (b>=1073741824) printf "%.1f GB", b/1073741824; else printf "%.0f MB", b/1048576 }'; }

status_text() {
  local b pct st temp health ramt rama dsk_t dsk_f cloud up ip ts_state svc line
  b=$(timeout 20 termux-battery-status 2>/dev/null)
  pct=$(jq -r '.percentage // "?"' <<<"$b" 2>/dev/null)
  st=$(jq -r '.status // "?"' <<<"$b" 2>/dev/null)
  temp=$(jq -r '.temperature // "?"' <<<"$b" 2>/dev/null)
  health=$(jq -r '.health // "?"' <<<"$b" 2>/dev/null)
  case "$st" in CHARGING) st="carregando";; DISCHARGING) st="descarregando";; FULL) st="cheia";; NOT_CHARGING) st="não carrega";; esac
  case "$health" in GOOD) health="boa";; OVERHEAT) health="SUPERAQUECIDA";; DEAD) health="ruim";; COLD) health="fria";; esac
  line="🔋 Bateria: ${pct}% ($st), ${temp} °C, saúde $health"
  awk -v t="$temp" 'BEGIN{exit !(t+0>=40)}' 2>/dev/null && line="$line"$'\n'"⚠️ Bateria quente!"
  [ "$pct" != "?" ] && [ "$pct" -lt 20 ] 2>/dev/null && [ "$st" = "descarregando" ] && line="$line"$'\n'"⚠️ Bateria baixa e sem carregador!"

  read -r ramt rama < <(awk '/^MemTotal/{t=$2}/^MemAvailable/{a=$2}END{print t*1024, a*1024}' /proc/meminfo)
  read -r dsk_t dsk_f < <(df -k "$H" | awk 'NR==2{print $2*1024, $4*1024}')
  cloud=""
  [ -s "$H/cloud/.nuvem-status.json" ] && cloud=$(jq -r '.cloud // empty' "$H/cloud/.nuvem-status.json" 2>/dev/null)
  # /proc/uptime não é legível pelo Termux; o comando uptime funciona
  up=$(uptime -p 2>/dev/null | sed -E 's/^up //; s/ weeks?/sem/; s/ days?/d/; s/ hours?/h/; s/ minutes?/min/; s/,//g')
  [ -z "$up" ] && up="?"

  ip=$(timeout 5 ts ip -4 2>/dev/null | head -1)
  ts_state=$(timeout 8 ts status --json 2>/dev/null | jq -r '.BackendState // empty' 2>/dev/null)
  svc=""
  pgrep -x sshd >/dev/null && svc="$svc ✅sshd" || svc="$svc ❌sshd"
  pgrep -f 'bin/dufs' >/dev/null && svc="$svc ✅dufs" || svc="$svc ❌dufs"
  pgrep -f 'bin/tailscaled' >/dev/null && svc="$svc ✅tailscaled" || svc="$svc ❌tailscaled"
  if [ -f "$H/.dnsblock/dnsblock.py" ]; then   # só aparece se o bloqueador estiver instalado
    pgrep -f 'dnsblock[.]py' >/dev/null && svc="$svc ✅dns" || svc="$svc ❌dns"
  fi

  printf '%s\n🧠 RAM: %s disponíveis de %s\n💾 Disco: %s livres de %s' "$line" "$(human "$rama")" "$(human "$ramt")" "$(human "$dsk_f")" "$(human "$dsk_t")"
  [ -n "$cloud" ] && printf ' (Nuvem: %s)' "$(human "$cloud")"
  printf '\n⏱ Ligado há %s\n🌐 Tailscale: %s %s\n⚙️ Serviços:%s' "$up" "${ts_state:-?}" "${ip:+($ip)}" "$svc"
}

if [ "$1" = "--status" ]; then status_text; echo; exit 0; fi

[ -f "$D/config" ] || { echo "falta $D/config"; exit 1; }
# shellcheck disable=SC1091
. "$D/config"
[ -n "$TOKEN" ] && [ -n "$OWNER_ID" ] || { echo "config incompleta"; exit 1; }
API="https://api.telegram.org/bot$TOKEN"

# O token entra por stdin (-K -), assim não aparece na lista de processos.
tg() { local m=$1; shift; printf 'url = "%s/%s"\n' "$API" "$m" | curl -sS -m 70 -K - "$@"; }
send() { tg sendMessage --data-urlencode "chat_id=$OWNER_ID" --data-urlencode "text=$1" >/dev/null 2>>"$D/bot.log"; }
send_ok() { [ "$(tg sendMessage -m 15 --data-urlencode "chat_id=$OWNER_ID" --data-urlencode "text=$1" 2>>"$D/bot.log" | jq -r '.ok // false')" = true ]; }   # true só se o Telegram aceitou

FOTO_FLASH_WAIT=45   # segundos esperando o app de flash devolver a foto

foto_flash() {   # $1=arquivo de saída. Pede a foto ao app J4 FlashCam (flashcam/) e a recebe em 127.0.0.1.
  local f=$1 port key srv
  port=$((20000 + RANDOM % 20000)); key=$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')
  rm -f "$f" "$f.err"
  python3 - "$port" "$key" "$f" "$FOTO_FLASH_WAIT" <<'PY' &
import sys, time, http.server
port, key, out, wait = int(sys.argv[1]), sys.argv[2], sys.argv[3], float(sys.argv[4])
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        if self.path != '/' + key or n > 30000000:   # só aceita quem sabe a chave desta foto
            self.send_response(403); self.end_headers(); return
        data = self.rfile.read(n)
        open(out if self.headers.get('X-Result') == 'ok' else out + '.err', 'wb').write(data)
        self.send_response(200); self.end_headers(); self.server.done = True
    def log_message(self, *a): pass
s = http.server.HTTPServer(('127.0.0.1', port), H); s.done = False; s.timeout = 1
end = time.time() + wait
while not s.done and time.time() < end: s.handle_request()
PY
  srv=$!
  sleep 0.5   # deixa o servidor começar a escutar
  if ! am start -n com.j4.flashcam/.FlashActivity --ei port "$port" --es key "$key" >"$D/tmp/am.out" 2>&1 || grep -qiE 'error|exception' "$D/tmp/am.out"; then
    log "foto flash: am start falhou: $(head -c 200 "$D/tmp/am.out")"
    kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null
    return 2
  fi
  wait "$srv"
  [ -s "$f" ]
}

cmd_foto() {   # $1 = argumentos: frente|frontal e/ou flash|luz|lanterna
  local cam=0 label=traseira f="$D/tmp/foto.jpg" flash=0 w ws rc
  read -ra ws <<<"$1"
  for w in "${ws[@]}"; do case "${w,,}" in
    frente|frontal) cam=1; label=frontal;;
    flash|luz|lanterna) flash=1;;
  esac; done
  if [ $flash = 1 ] && [ $cam = 1 ]; then send "A câmera frontal não tem flash. Use /foto flash (traseira)."; return; fi
  rm -f "$f"
  tg sendChatAction --data-urlencode "chat_id=$OWNER_ID" --data-urlencode "action=upload_photo" >/dev/null 2>&1
  if [ $flash = 1 ]; then
    foto_flash "$f"; rc=$?
    if [ $rc = 2 ]; then send "Não consegui abrir o app de flash. Ele está instalado? (flashcam/install.sh no PC; veja docs/16)"; rm -f "$f" "$f.err"; return; fi
    if [ $rc != 0 ]; then send "Não consegui tirar a foto com flash: $(head -c 200 "$f.err" 2>/dev/null || echo 'sem resposta do app')"; rm -f "$f" "$f.err"; return; fi
    label="traseira com flash"
  elif ! { timeout 60 termux-camera-photo -c "$cam" "$f" 2>>"$D/bot.log" && [ -s "$f" ]; }; then
    send "Não consegui tirar a foto (câmera ocupada ou sem permissão)."; rm -f "$f"; return
  fi
  tg sendPhoto -m 150 -F "chat_id=$OWNER_ID" -F "photo=@$f" -F "caption=📷 Câmera $label · $(date '+%d/%m/%Y %H:%M:%S')" >/dev/null 2>>"$D/bot.log" \
    || send "Tirei a foto, mas não consegui enviar."
  rm -f "$f" "$f.err"   # a foto nunca fica guardada no celular
}

SOUND_DIRS="/system/media/audio/ringtones /system/media/audio/notifications"
find_sound() {   # $1=nome sem .ogg (maiúsculas tanto faz); imprime o caminho do arquivo
  local d f want=${1,,}
  for d in $SOUND_DIRS; do
    for f in "$d"/*.ogg; do
      [ -f "$f" ] || continue
      f=${f##*/}; f=${f%.ogg}
      [ "${f,,}" = "$want" ] && { echo "$d/$f.ogg"; return 0; }
    done
  done
  return 1
}
cmd_tocar() {
  local name="$1" d f=""
  if [ "$name" = "lista" ]; then
    send "🎵 Sons disponíveis (use /tocar nome):"$'\n'"$(for d in $SOUND_DIRS; do ls "$d" 2>/dev/null; done | sed 's/\.ogg$//' | sort -u | tr '\n' ' ')"
    return
  fi
  [ -z "$name" ] && name="Basic_Bell"
  if [[ ! "$name" =~ ^[A-Za-z0-9_-]{1,40}$ ]]; then send "Nome de som inválido. Use /tocar lista."; return; fi
  f=$(find_sound "$name") || { send "Não achei o som “$name”. Use /tocar lista."; return; }
  termux-volume music 13 >/dev/null 2>&1
  termux-media-player play "$f" >/dev/null 2>&1 && send "🔔 Tocando $name (use /parar para silenciar)." || send "Não consegui tocar o som."
}

# ---------- Despertador ----------
# Arquivo $D/alarms, uma linha por despertador: id|HH:MM|modo|som|ultimo_dia_disparado
# modo: once (uma vez) | daily (todo dia) | weekdays (seg-sex) | weekend (sáb-dom)
ALARMS="$D/alarms"
ALARM_SOUND_DEFAULT="Morning_Glory"
RING_MAX=40    # repetições do toque (~8 s cada, uns 5 min no total)

lock()   { local i=0; until mkdir "$D/alarms.lock" 2>/dev/null; do sleep 0.2; i=$((i+1)); [ $i -gt 25 ] && rmdir "$D/alarms.lock" 2>/dev/null; done; }
unlock() { rmdir "$D/alarms.lock" 2>/dev/null; }

mode_label() { case "$1" in once) echo "uma vez";; daily) echo "todo dia";; weekdays) echo "seg–sex";; weekend) echo "sáb–dom";; esac; }
mode_ok() {   # $1=modo $2=dia da semana (1=seg..7=dom)
  case "$1" in weekdays) [ "$2" -le 5 ];; weekend) [ "$2" -ge 6 ];; *) true;; esac
}

stop_ring() {
  local p; p=$(cat "$D/ring.pid" 2>/dev/null)
  [ -n "$p" ] && kill "$p" 2>/dev/null
  rm -f "$D/ring.pid"
  termux-media-player stop >/dev/null 2>&1
}

ring() {   # $1=arquivo de som; toca repetido até /parar ou RING_MAX
  stop_ring
  : > "$D/ring.pid"   # o marcador precisa existir antes do laço começar
  (
    i=0
    while [ $i -lt $RING_MAX ] && [ -f "$D/ring.pid" ]; do
      termux-volume music 15 >/dev/null 2>&1
      termux-media-player stop >/dev/null 2>&1
      termux-media-player play "$1" >/dev/null 2>&1
      sleep 8; i=$((i+1))
    done
    rm -f "$D/ring.pid"
  ) &
  echo $! > "$D/ring.pid"
}

alarm_loop() {   # roda em segundo plano; confere a cada 15 s
  local now today dow id t mode snd last f out
  while true; do
    sleep 15
    [ -s "$ALARMS" ] || continue
    now=$(date +%H:%M); today=$(date +%F); dow=$(date +%u)
    lock
    out="$D/alarms.new"; : > "$out"
    while IFS='|' read -r id t mode snd last; do
      [ -z "$id" ] && continue
      if [ "$t" = "$now" ] && [ "$last" != "$today" ] && mode_ok "$mode" "$dow"; then
        f=$(find_sound "$snd") || f=$(find_sound "$ALARM_SOUND_DEFAULT")
        log "despertador $id disparou ($t $snd)"
        [ -n "$f" ] && ring "$f"
        send "⏰ Despertador $t! Use /parar para silenciar."
        [ "$mode" = once ] && continue    # uma vez: apaga depois de tocar
        last=$today
      fi
      printf '%s|%s|%s|%s|%s\n' "$id" "$t" "$mode" "$snd" "$last" >> "$out"
    done < "$ALARMS"
    mv "$out" "$ALARMS"
    unlock
  done
}

cmd_despertador() {
  local args="$1" orig f w t="" mode=once snd="$ALARM_SOUND_DEFAULT" h m id last now today n
  read -ra w <<<"$args"
  case "${w[0],,}" in
    ""|lista)
      if [ ! -s "$ALARMS" ]; then send $'⏰ Nenhum despertador.\nCrie com: /despertador 07:30 (veja /ajuda)'; return; fi
      now=$(date +%H:%M)
      send "⏰ Despertadores:"$'\n'"$(while IFS='|' read -r id t mode snd last; do
        printf '%s) %s · %s · %s\n' "$id" "$t" "$(mode_label "$mode")" "$snd"; done < "$ALARMS")"$'\n'"Apagar: /despertador apagar N (ou todos)"
      return;;
    apagar|apaga|cancelar|remover)
      id="${w[1],,}"
      if [ "$id" = todos ]; then lock; : > "$ALARMS"; unlock; send "🗑 Todos os despertadores apagados."; return; fi
      if [[ ! "$id" =~ ^[0-9]+$ ]] || ! grep -q "^$id|" "$ALARMS" 2>/dev/null; then send "Não achei esse número. Veja /despertador lista."; return; fi
      lock; grep -v "^$id|" "$ALARMS" > "$ALARMS.new"; mv "$ALARMS.new" "$ALARMS"; unlock
      send "🗑 Despertador $id apagado."; return;;
  esac
  for n in "${w[@]}"; do
    orig=$n; n=${n,,}
    # horário: 7, 7h, 7:30, 07:30 ou 7h30
    if [[ "$n" =~ ^([01]?[0-9]|2[0-3])((:|h)([0-5][0-9])|h)?$ ]] && [ -z "$t" ]; then
      h=$((10#${BASH_REMATCH[1]})); m=$((10#${BASH_REMATCH[4]:-0})); t=$(printf '%02d:%02d' "$h" "$m")
    else case "$n" in
      diario|diaria|todo|todos) mode=daily;;
      semana|uteis|úteis) mode=weekdays;;
      fds|fimdesemana) mode=weekend;;
      uma|once|unico|único) mode=once;;
      *) if [[ "$orig" =~ ^[A-Za-z0-9_-]{1,40}$ ]] && f=$(find_sound "$orig"); then snd=${f##*/}; snd=${snd%.ogg}
         else send "Não entendi “$n”. Exemplos: /despertador 07:30, /despertador 6:45 semana Rush, /despertador lista"; return; fi;;
    esac; fi
  done
  [ -z "$t" ] && { send "Faltou o horário. Exemplo: /despertador 07:30"; return; }
  lock
  id=$(( $(cut -d'|' -f1 "$ALARMS" 2>/dev/null | sort -n | tail -1) + 1 ))
  now=$(date +%H:%M); today=$(date +%F); last=""
  # se o horário de hoje já passou (ou é agora), a primeira vez é amanhã
  [[ ! "$t" > "$now" ]] && last=$today
  printf '%s|%s|%s|%s|%s\n' "$id" "$t" "$mode" "$snd" "$last" >> "$ALARMS"
  unlock
  send "⏰ Despertador $id criado: $t · $(mode_label "$mode") · som $snd"$'\n'"Próxima vez: $([ -n "$last" ] && echo "a partir de amanhã" || echo "hoje")"
}

# ---------- Lembretes (mensagem de texto + toque curto) ----------
# Arquivo $D/reminders, uma linha por lembrete:
#   uma vez:    id|epoch|once||texto
#   recorrente: id|HH:MM|daily/weekdays/weekend|ultimo_dia_disparado|texto
# O texto fica por último porque pode ter "|".
REMINDERS="$D/reminders"
DIAS=(dom seg ter qua qui sex sáb)
REMINDER_SOUND="Ding_Dong"   # sininho curto; diferente do toque longo do despertador
REMINDER_BEEP_SECS=10        # toca por 10 s e para sozinho
TIME_RE='^([01]?[0-9]|2[0-3])(:([0-5][0-9])|h([0-5][0-9])?)$'

rlock()   { local i=0; until mkdir "$D/reminders.lock" 2>/dev/null; do sleep 0.2; i=$((i+1)); [ $i -gt 75 ] && rmdir "$D/reminders.lock" 2>/dev/null; done; }
runlock() { rmdir "$D/reminders.lock" 2>/dev/null; }

beep_reminder() {   # toca REMINDER_SOUND repetido por REMINDER_BEEP_SECS e para; /parar corta
  local f; f=$(find_sound "$REMINDER_SOUND") || return 0
  [ -f "$D/ring.pid" ] && return 0   # um alarme (ou outro lembrete) já está tocando: não atrapalha
  : > "$D/ring.pid"
  (
    n=$(( (REMINDER_BEEP_SECS * 2 + 4) / 5 )); i=0   # um toque a cada 2,5 s
    termux-volume music 13 >/dev/null 2>&1
    while [ $i -lt $n ] && [ -f "$D/ring.pid" ]; do
      termux-media-player stop >/dev/null 2>&1
      termux-media-player play "$f" >/dev/null 2>&1
      sleep 2.5; i=$((i+1))
    done
    termux-media-player stop >/dev/null 2>&1
    rm -f "$D/ring.pid"
  ) &
  echo $! > "$D/ring.pid"
}

fmt_when() { echo "${DIAS[$(date -d "@$1" +%w)]} $(date -d "@$1" '+%d/%m %H:%M')"; }

rel_seconds() {   # 30min, 45m, 2h, 1h30, 1h30min, 2d -> segundos
  local n=${1,,}
  if   [[ "$n" =~ ^([0-9]{1,4})(min|m)$ ]]; then echo $((10#${BASH_REMATCH[1]} * 60))
  elif [[ "$n" =~ ^([0-9]{1,3})h([0-9]{1,2})?(min|m)?$ ]]; then echo $((10#${BASH_REMATCH[1]} * 3600 + 10#${BASH_REMATCH[2]:-0} * 60))
  elif [[ "$n" =~ ^([0-9]{1,3})d$ ]]; then echo $((10#${BASH_REMATCH[1]} * 86400))
  else return 1; fi
}

rdate() {   # hoje, amanhã, dia da semana ou dd/mm[/aaaa] -> AAAA-MM-DD. Retorna 1 se não é data, 2 se é data inválida
  local n=${1,,} wd="" d m y s out
  case "$n" in
    hoje) date +%F; return 0;;
    amanha|amanhã) date -d tomorrow +%F; return 0;;
    segunda|segunda-feira) wd=monday;;
    terca|terça|terca-feira|terça-feira) wd=tuesday;;
    quarta|quarta-feira) wd=wednesday;;
    quinta|quinta-feira) wd=thursday;;
    sexta|sexta-feira) wd=friday;;
    sabado|sábado) wd=saturday;;
    domingo) wd=sunday;;
  esac
  if [ -n "$wd" ]; then date -d "next $wd" +%F; return 0; fi    # sempre a próxima ocorrência (nunca hoje)
  [[ "$n" =~ ^([0-9]{1,2})/([0-9]{1,2})(/([0-9]{4}))?$ ]] || return 1
  d=$((10#${BASH_REMATCH[1]})); m=$((10#${BASH_REMATCH[2]})); y=${BASH_REMATCH[4]}
  if [ -n "$y" ]; then
    printf -v s '%04d-%02d-%02d' "$y" "$m" "$d"
    out=$(date -d "$s" +%F 2>/dev/null) && [ "$out" = "$s" ] && { echo "$s"; return 0; }
    return 2
  fi
  y=$(date +%Y)
  printf -v s '%04d-%02d-%02d' "$y" "$m" "$d"
  out=$(date -d "$s" +%F 2>/dev/null) && [ "$out" = "$s" ] || return 2
  if [[ "$s" < "$(date +%F)" ]]; then   # já passou este ano: vale o próximo
    printf -v s '%04d-%02d-%02d' $((y+1)) "$m" "$d"
    out=$(date -d "$s" +%F 2>/dev/null) && [ "$out" = "$s" ] || return 2
  fi
  echo "$s"
}

reminder_loop() {   # roda em segundo plano; confere a cada 15 s. Lembrete atrasado (bot/celular fora do ar) ainda é entregue.
  local now_s now today dow id when mode last text out msg
  while true; do
    sleep 15
    [ -s "$REMINDERS" ] || continue
    now_s=$(date +%s); now=$(date +%H:%M); today=$(date +%F); dow=$(date +%u)
    rlock
    out="$D/reminders.new"; : > "$out"
    while IFS='|' read -r id when mode last text; do
      [ -z "$id" ] && continue
      if [ "$mode" = once ]; then
        if [[ "$when" =~ ^[0-9]+$ ]] && [ "$when" -le "$now_s" ]; then
          msg="🔔 Lembrete: $text"
          [ $((now_s - when)) -gt 300 ] && msg="$msg"$'\n'"(era para $(fmt_when "$when"); o servidor estava fora do ar)"
          if send_ok "$msg"; then log "lembrete $id enviado"; beep_reminder; continue; fi   # se o envio falhar, fica para a próxima rodada
        fi
      elif [[ ! "$now" < "$when" ]] && [ "$last" != "$today" ] && mode_ok "$mode" "$dow"; then
        if send_ok "🔔 Lembrete: $text"; then last=$today; log "lembrete $id enviado"; beep_reminder; fi
      fi
      printf '%s|%s|%s|%s|%s\n' "$id" "$when" "$mode" "$last" "$text" >> "$out"
    done < "$REMINDERS"
    mv "$out" "$REMINDERS"
    runlock
  done
}

cmd_lembrar() {
  local args="$1" w n i=0 t="" dt="" rel="" mode=once text="" id last now today h m tgt now_s rc d
  read -ra w <<<"$args"
  case "${w[0],,}" in
    ""|lista)
      if [ ! -s "$REMINDERS" ]; then send $'🔔 Nenhum lembrete.\nCrie com: /lembrar amanhã 9h pagar a luz (veja /ajuda)'; return; fi
      send "🔔 Lembretes:"$'\n'"$(while IFS='|' read -r id t mode last text; do
        if [ "$mode" = once ]; then printf '%s) %s · %s\n' "$id" "$(fmt_when "$t")" "$text"
        else printf '%s) %s %s · %s\n' "$id" "$(mode_label "$mode")" "$t" "$text"; fi; done < "$REMINDERS")"$'\n'"Apagar: /lembrar apagar N (ou todos)"
      return;;
    apagar|apaga|cancelar|remover)
      id="${w[1],,}"
      if [ "$id" = todos ]; then rlock; : > "$REMINDERS"; runlock; send "🗑 Todos os lembretes apagados."; return; fi
      if [[ ! "$id" =~ ^[0-9]+$ ]] || ! grep -q "^$id|" "$REMINDERS" 2>/dev/null; then send "Não achei esse número. Veja /lembrar lista."; return; fi
      rlock; grep -v "^$id|" "$REMINDERS" > "$REMINDERS.new"; mv "$REMINDERS.new" "$REMINDERS"; runlock
      send "🗑 Lembrete $id apagado."; return;;
  esac
  # prefixo: [em 30min | data | horário | diario|semana|fds]; o resto é o texto
  while [ $i -lt ${#w[@]} ]; do
    n=${w[$i],,}
    if [ "$n" = em ] && [ -z "$rel$t$dt" ] && [ "$mode" = once ]; then
      i=$((i+1))
      rel=$(rel_seconds "${w[$i]:-}") && [ "$rel" -gt 0 ] || { send "Não entendi a duração. Exemplos: em 30min, em 2h, em 1h30, em 2d"; return; }
      i=$((i+1)); continue
    fi
    if [ -z "$t" ] && [ -z "$rel" ] && [[ "$n" =~ $TIME_RE ]]; then
      h=$((10#${BASH_REMATCH[1]})); m=$((10#${BASH_REMATCH[3]:-${BASH_REMATCH[4]:-0}})); t=$(printf '%02d:%02d' "$h" "$m")
      i=$((i+1)); continue
    fi
    if [ -z "$dt" ] && [ -z "$rel" ] && [ "$mode" = once ]; then
      d=$(rdate "$n"); rc=$?
      if [ $rc = 0 ]; then dt=$d; i=$((i+1)); continue; fi
      if [ $rc = 2 ]; then send "Essa data não existe: $n"; return; fi
    fi
    if [ "$mode" = once ] && [ -z "$rel" ] && [ -z "$dt" ]; then
      case "$n" in
        diario|diaria|diário|diária|todos) mode=daily; i=$((i+1)); continue;;
        todo) mode=daily; [ "${w[$((i+1))],,}" = dia ] && i=$((i+1)); i=$((i+1)); continue;;
        semana|uteis|úteis) mode=weekdays; i=$((i+1)); continue;;
        fds|fimdesemana) mode=weekend; i=$((i+1)); continue;;
      esac
    fi
    break
  done
  text="${w[*]:$i}"
  [ -z "$text" ] && { send $'Faltou o texto do lembrete.\nExemplo: /lembrar amanhã 9h pagar a luz'; return; }
  [ ${#text} -gt 500 ] && { send "Texto muito longo (máximo 500 caracteres)."; return; }
  now_s=$(date +%s); today=$(date +%F); now=$(date +%H:%M); last=""

  if [ "$mode" != once ]; then
    [ -z "$t" ] && { send "Falta o horário. Exemplo: /lembrar diario 8h tomar remédio"; return; }
    [[ ! "$t" > "$now" ]] && last=$today   # o horário de hoje já passou: a primeira vez é amanhã
    rlock
    id=$(( $(cut -d'|' -f1 "$REMINDERS" 2>/dev/null | sort -n | tail -1) + 1 ))
    printf '%s|%s|%s|%s|%s\n' "$id" "$t" "$mode" "$last" "$text" >> "$REMINDERS"; runlock
    send "🔔 Lembrete $id criado: $(mode_label "$mode") às $t · $text"; return
  fi

  if [ -n "$rel" ]; then tgt=$((now_s + rel))
  else
    [ -z "$t" ] && [ -z "$dt" ] && { send $'Faltou quando.\nExemplos: /lembrar 18h ligar pro João · /lembrar amanhã 9h pagar a luz · /lembrar 25/12 comprar presente · /lembrar em 30min tirar a roupa'; return; }
    [ -z "$t" ] && t=09:00   # só a data: 9h da manhã
    if [ -z "$dt" ]; then   # só o horário: hoje, ou amanhã se já passou
      tgt=$(date -d "$today $t" +%s)
      [ "$tgt" -le "$now_s" ] && tgt=$(date -d "$(date -d tomorrow +%F) $t" +%s)
    else tgt=$(date -d "$dt $t" +%s) || { send "Não entendi a data."; return; }
    fi
  fi
  [ "$tgt" -le "$now_s" ] && { send "Esse horário já passou ($(fmt_when "$tgt"))."; return; }
  rlock
  id=$(( $(cut -d'|' -f1 "$REMINDERS" 2>/dev/null | sort -n | tail -1) + 1 ))
  printf '%s|%s|once||%s\n' "$id" "$tgt" "$text" >> "$REMINDERS"; runlock
  send "🔔 Lembrete $id criado para $(fmt_when "$tgt"): $text"
}

# ---------- Bloqueador de DNS (~/.dnsblock) ----------
DNSD=$H/.dnsblock

cmd_dns() {
  local j day today total blocked pct top n age state
  j=$DNSD/stats.json
  if [ ! -f "$DNSD/dnsblock.py" ]; then send "O bloqueador de DNS não está instalado."; return; fi
  pgrep -f 'dnsblock[.]py' >/dev/null && state="✅ ativo" || state="❌ parado"
  today=$(date +%F)
  day=$(jq -r '.day // empty' "$j" 2>/dev/null)
  if [ "$day" = "$today" ]; then
    total=$(jq -r '.total' "$j"); blocked=$(jq -r '.blocked' "$j")
    top=$(jq -r '.top[:8][] | "• \(.[0]) (\(.[1]))"' "$j" 2>/dev/null)
  else total=0; blocked=0; top=""; fi
  pct=$(awk -v t="$total" -v b="$blocked" 'BEGIN{ if (t>0) printf "%.0f", b*100/t; else print 0 }')
  n=$(grep -c '^0\.0\.0\.0 ' "$DNSD/blocklist.txt" 2>/dev/null)
  age=$(( ( $(date +%s) - $(stat -c %Y "$DNSD/blocklist.txt" 2>/dev/null || echo 0) ) / 86400 ))
  send "🛡 Bloqueador de DNS: $state"$'\n'"Hoje: $total consultas, $blocked bloqueadas (${pct}%)"$'\n'"Lista: ${n:-0} domínios (atualizada há ${age} d)"${top:+$'\n\n'"Mais bloqueados hoje:"$'\n'"$top"}
}

dns_probe() {   # 0 se o bloqueador responde (nome de saúde sempre bloqueado) e o tailscaled roda
  python3 -c '
import socket,sys
m=b"\x55\xaa\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x05saude\x08dnsblock\x07invalid\x00\x00\x01\x00\x01"
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.settimeout(4)
try:
    s.sendto(m,("127.0.0.1",5353)); r,_=s.recvfrom(512)
    sys.exit(0 if r[:2]==m[:2] and r[3]&15==0 and r[7]>=1 else 1)
except Exception: sys.exit(1)' 2>/dev/null
}

dns_watch() {   # avisa quando o bloqueador cai e quando volta; tenta reiniciar o run.sh se ele sumiu
  local fails=0 down=0 why
  [ -f "$DNSD/dnsblock.py" ] || return
  while sleep 30; do
    [ -f "$DNSD/disabled" ] && { fails=0; continue; }
    why=""
    dns_probe || why="o servidor DNS não responde"
    pgrep -f 'bin/tailscaled' >/dev/null || why="o tailscaled parou"
    if [ -z "$why" ]; then
      fails=0
      if [ "$down" = 1 ]; then down=0; send "✅ Bloqueador de DNS voltou ao normal."; fi
    else
      fails=$((fails+1))
      pgrep -f '[.]dnsblock/run[.]sh' >/dev/null || { nohup sh "$DNSD/run.sh" >/dev/null 2>&1 & log "dns_watch: run.sh reiniciado"; }
      if [ $fails -ge 2 ] && [ "$down" = 0 ]; then
        down=1
        send "⚠️ Bloqueador de DNS com problema: $why."$'\n'"Celulares com DNS privado podem ficar sem internet; se precisar, ponha o DNS privado em Automático. Tentando reiniciar."
      fi
    fi
  done
}

cmd_ajuda() {
  send $'🤖 Servidor J4\n/status: bateria, RAM, disco, rede e serviços\n/foto: foto da câmera traseira (/foto frente para a frontal, /foto flash para a traseira com flash)\n/tocar: faz o celular tocar (/tocar lista, /tocar nome)\n/despertador: /despertador 07:30 [diario|semana|fds] [som], /despertador lista, /despertador apagar N\n/lembrar: mensagem + toque de 10 s no horário. Ex.: /lembrar amanhã 9h pagar a luz · /lembrar em 30min · /lembrar 25/12 · /lembrar diario 8h remédio · /lembrar lista · /lembrar apagar N\n/dns: bloqueador de anúncios (consultas, bloqueios, mais bloqueados)\n/parar: silencia o som e o despertador\n/ajuda: esta mensagem'
}

handle() {
  local text="$1" cmd arg full=""
  cmd=${text%%[[:space:]]*}; cmd=${cmd%%@*}; cmd=${cmd,,}
  arg=""
  if [[ "$text" == *[[:space:]]* ]]; then
    arg=${text#*[[:space:]]}
    arg=${arg#"${arg%%[![:space:]]*}"}   # tira espaços do começo
    full=$arg                            # argumentos completos (despertador)
    arg=${arg%%[[:space:]]*}             # só a primeira palavra
  fi
  case "$cmd" in
    /start|/ajuda|/help) cmd_ajuda;;
    /status)  send "$(status_text)";;
    /foto)    cmd_foto "$full";;
    /tocar)   cmd_tocar "$arg";;
    /despertador|/alarme) cmd_despertador "$full";;
    /lembrar|/lembrete|/lembretes) cmd_lembrar "$full";;
    /dns)     cmd_dns;;
    /parar)   stop_ring; send "🔕 Som parado.";;
    *)        send "Não conheço esse comando. Use /ajuda.";;
  esac
}

# teste sem Telegram de verdade na entrada: bash bot.sh --foto [frente|flash]  (a foto vai para o seu Telegram)
if [ "$1" = --foto ]; then shift; cmd_foto "$*"; exit 0; fi

# valida o token antes de começar
me=$(tg getMe 2>>"$D/bot.log")
[ "$(jq -r '.ok // false' <<<"$me" 2>/dev/null)" = true ] || { log "token invalido ou sem rede"; sleep 30; exit 1; }
log "bot iniciado como @$(jq -r '.result.username' <<<"$me")"

# avisa quando o celular acabou de ligar (uma vez por boot). O script de boot
# grava a hora em boot_ts; /proc/stat não é legível pelo Termux.
bts=$(cat "$D/boot_ts" 2>/dev/null)
if [ -n "$bts" ] && [ "$(cat "$D/last_boot" 2>/dev/null)" != "$bts" ]; then
  echo "$bts" > "$D/last_boot"
  send "✅ Servidor ligado. Use /status para ver como está."
fi

# despertadores: laço separado, para não depender do getUpdates (que bloqueia ~50 s)
alarm_loop &
ALARM_PID=$!
reminder_loop &
REM_PID=$!
dns_watch &
DNSW_PID=$!
trap 'kill $ALARM_PID $REM_PID $DNSW_PID 2>/dev/null; rmdir "$D/alarms.lock" "$D/reminders.lock" 2>/dev/null' EXIT

offset=$(cat "$D/offset" 2>/dev/null || echo 0)
while true; do
  [ "$(stat -c %s "$D/bot.log" 2>/dev/null || echo 0)" -gt 200000 ] && tail -n 200 "$D/bot.log" > "$D/bot.log.tmp" && mv "$D/bot.log.tmp" "$D/bot.log"
  resp=$(tg getUpdates --data-urlencode "offset=$offset" --data-urlencode "timeout=50" --data-urlencode 'allowed_updates=["message"]' 2>>"$D/bot.log")
  if [ "$(jq -r '.ok // false' <<<"$resp" 2>/dev/null)" != true ]; then sleep 10; continue; fi
  while IFS= read -r u; do
    [ -z "$u" ] && continue
    id=$(jq -r '.update_id' <<<"$u"); offset=$((id + 1)); echo "$offset" > "$D/offset"
    from=$(jq -r '.message.from.id // empty' <<<"$u"); chat=$(jq -r '.message.chat.id // empty' <<<"$u")
    text=$(jq -r '.message.text // empty' <<<"$u")
    if [ "$from" != "$OWNER_ID" ] || [ "$chat" != "$OWNER_ID" ]; then log "ignorado: remetente $from"; continue; fi
    [ -n "$text" ] && handle "$text"
  done < <(jq -c '.result[]' <<<"$resp")
done
