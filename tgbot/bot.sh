#!/data/data/com.termux/files/usr/bin/bash
# Bot do Telegram do servidor J4 (roda no Termux).
# Config: ~/.tgbot/config com TOKEN e OWNER_ID. Só o OWNER_ID é atendido.
# Comandos: /status /foto [frente] /tocar [nome|lista] /despertador /dns /parar /ajuda
# Teste sem Telegram: bash bot.sh --status
export PATH=/data/data/com.termux/files/usr/bin:$PATH
H=/data/data/com.termux/files/home
D=$H/.tgbot
mkdir -p "$D/tmp"; chmod 700 "$D" "$D/tmp"

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

cmd_foto() {
  local cam=0 label=traseira f="$D/tmp/foto.jpg"
  case "$1" in frente|frontal) cam=1; label=frontal;; esac
  rm -f "$f"
  tg sendChatAction --data-urlencode "chat_id=$OWNER_ID" --data-urlencode "action=upload_photo" >/dev/null 2>&1
  if timeout 60 termux-camera-photo -c "$cam" "$f" 2>>"$D/bot.log" && [ -s "$f" ]; then
    tg sendPhoto -m 150 -F "chat_id=$OWNER_ID" -F "photo=@$f" -F "caption=📷 Câmera $label · $(date '+%d/%m/%Y %H:%M:%S')" >/dev/null 2>>"$D/bot.log" \
      || send "Tirei a foto, mas não consegui enviar."
  else
    send "Não consegui tirar a foto (câmera ocupada ou sem permissão)."
  fi
  rm -f "$f"   # a foto nunca fica guardada no celular
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
  send $'🤖 Servidor J4\n/status: bateria, RAM, disco, rede e serviços\n/foto: foto da câmera traseira (/foto frente para a frontal)\n/tocar: faz o celular tocar (/tocar lista, /tocar nome)\n/despertador: /despertador 07:30 [diario|semana|fds] [som], /despertador lista, /despertador apagar N\n/dns: bloqueador de anúncios (consultas, bloqueios, mais bloqueados)\n/parar: silencia o som e o despertador\n/ajuda: esta mensagem'
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
    /foto)    cmd_foto "${arg,,}";;
    /tocar)   cmd_tocar "$arg";;
    /despertador|/alarme) cmd_despertador "$full";;
    /dns)     cmd_dns;;
    /parar)   stop_ring; send "🔕 Som parado.";;
    *)        send "Não conheço esse comando. Use /ajuda.";;
  esac
}

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
dns_watch &
DNSW_PID=$!
trap 'kill $ALARM_PID $DNSW_PID 2>/dev/null; rmdir "$D/alarms.lock" 2>/dev/null' EXIT

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
