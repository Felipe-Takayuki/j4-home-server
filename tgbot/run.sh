#!/data/data/com.termux/files/usr/bin/sh
# Mantém o bot vivo: se ele cair, sobe de novo em 5 s. Para sozinho se a config sumir.
D=/data/data/com.termux/files/home/.tgbot
B=/data/data/com.termux/files/usr/bin
while [ -f "$D/config" ]; do
  $B/bash "$D/bot.sh" >> "$D/bot.log" 2>&1
  sleep 5
done
