# 08 — The Telegram bot

[`tgbot/bot.sh`](../tgbot/bot.sh) is a ~300-line Bash script that long-polls the Telegram Bot API and answers **only its owner**.
It is outbound-only (no webhook, no open port), uses `curl` + `jq`, and talks to the phone through [Termux:API](https://wiki.termux.com/wiki/Termux:API).
Messages are in Brazilian Portuguese.

## Commands

| Command | What it does |
|---|---|
| `/status` | battery (level, charging state, temperature, health, warnings above 40 °C or below 20 % unplugged), RAM, disk, uptime, Tailscale state/IP, and whether `sshd`, `dufs`, `tailscaled` and (if installed) the `dns` ad blocker are running |
| `/foto` / `/foto frente` | takes a photo with the rear (or front) camera and sends it; the photo is deleted from the phone right after sending. Works with the screen off |
| `/tocar [nome]` / `/tocar lista` | plays a built-in Android ringtone/notification sound (default `Basic_Bell`); `lista` shows the names |
| `/despertador …` | alarm clock, see [09](09-alarm-clock.md) (`/alarme` is an alias) |
| `/dns` | ad-blocker status and today's numbers, see [10](10-dns-adblocker.md) |
| `/lembrar …` | text reminder at a given time (plus a 10 s chime), see [15](15-reminders.md) (`/lembretes` is an alias) |
| `/parar` | stops any sound, including a ringing alarm |
| `/ajuda` | lists the commands |

At start-up (once per boot, detected through a timestamp the boot script writes) it sends "✅ Servidor ligado". A background loop also
watches the DNS blocker and alerts you when it fails ([10](10-dns-adblocker.md)).

## Setup

1. **Create the bot**: in Telegram talk to [@BotFather](https://t.me/BotFather) → `/newbot`. Copy the **token** it gives you.
2. **Find your numeric user id**. Without a third-party bot: send any message to your new bot, then on the PC run
   `curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates"` and read `message.from.id`. (Do this on your own machine and do not paste the token anywhere.)
3. **Install Termux:API** (the Android app, same source as Termux) and grant it **only the `CAMERA` permission** the bot needs for `/foto`.
   In Termux: `pkg install termux-api jq curl`.
4. **Install the bot**: `tools/adb-run.sh install/tgbot.sh`. It warns about missing commands and tells you the config file is missing.
5. **Create the config on the phone** — type it in Termux, or over SSH, **not** through a shared script or chat:
   ```sh
   mkdir -p ~/.tgbot && chmod 700 ~/.tgbot
   umask 077
   cat > ~/.tgbot/config <<'EOF'
   TOKEN="<your token>"
   OWNER_ID="<your numeric id>"
   EOF
   sh ~/.termux/boot/50-tgbot
   ```
   ([`tgbot/config.example`](../tgbot/config.example) shows the format.) The supervisor stops by itself if the config file disappears.
6. Send `/ajuda` to the bot.

## How it stays safe

- **Owner only.** For every update the script compares both `message.from.id` *and* `message.chat.id` with `OWNER_ID`; anything else is ignored
  (the log records only the sender id, never the text).
- **The token is not on the command line.** Requests pipe `url = "https://api.telegram.org/bot<TOKEN>/<method>"` into `curl -K -`, so it never shows in
  `ps`.
- **Sound names are validated** with `^[A-Za-z0-9_-]{1,40}$` and looked up in fixed system directories; no user text reaches a shell.
- The bot's own log (`~/.tgbot/bot.log`) is trimmed above 200 KB.
- If the token leaks, revoke it in BotFather (`/revoke`) and update the config.

## Files on the phone

| Path | Purpose |
|---|---|
| `~/.tgbot/bot.sh`, `run.sh` | the bot and its 5-second supervisor loop |
| `~/.tgbot/config` | token and owner id (`chmod 600`) |
| `~/.tgbot/offset` | last Telegram update id handled |
| `~/.tgbot/alarms` | alarm clock data ([09](09-alarm-clock.md)) |
| `~/.tgbot/reminders` | text reminders ([15](15-reminders.md)) |
| `~/.tgbot/boot_ts`, `last_boot` | detect "first start after a boot" |
| `~/.termux/boot/50-tgbot` | starts the supervisor at boot |

## Hacking on it

- Run `bash tgbot/bot.sh --status` (on the phone) to print the `/status` text without Telegram.
- A new command is a `cmd_xxx` function plus one line in `handle()`. Only the first word of the arguments is passed as `$arg`; the whole text is in `$full`.
- Pure-logic parts (alarm parsing/scheduling) are covered by `tests/test_alarm.sh` and `tests/test_reminders.sh`.
