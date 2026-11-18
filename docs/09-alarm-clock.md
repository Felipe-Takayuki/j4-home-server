# 09 — Alarm clock

Set an alarm from Telegram; at that time the phone rings (looping, at full music volume) until you send `/parar`, and the bot messages you.
It uses the sounds already on the phone, so the J4 becomes a bedside alarm that is reachable from anywhere.

## Usage

```
/despertador 07:30                  one-shot: the next 07:30 (today if still ahead, otherwise tomorrow), then it is deleted
/despertador 05:40 diario           every day
/despertador 6h45 semana Rush       Monday–Friday, with the "Rush" sound
/despertador 8 fds                  Saturday and Sunday at 08:00
/despertador lista                  list alarms with their numbers
/despertador apagar 2               delete alarm 2   (or: apagar todos)
/parar                              silence the ringing alarm
```

- **Time formats:** `7`, `7h`, `7:30`, `07:30`, `7h30` (24-hour clock).
- **Modes:** `uma vez` (default), `diario`/`todo`, `semana`/`uteis` (Mon–Fri), `fds` (Sat–Sun). Words can come in any order.
- **Sound:** the name of any file in `/system/media/audio/ringtones` or `notifications`, case-insensitive (`/tocar lista` prints them).
  Default: `Morning_Glory`.
- An alarm set for a time that already passed today (or *this very minute*) first rings **tomorrow**.

## How it works

- Alarms live in `~/.tgbot/alarms`, one line each: `id|HH:MM|mode|sound|last_day_fired`. Changes go through a tiny `mkdir`-based lock because both the
  chat handler and the checker write the file.
- `alarm_loop` is a background function of `bot.sh` that wakes every **15 seconds**, compares `date +%H:%M` with every alarm and fires the ones that match and
  have not fired today (so a minute is never rung twice). One-shot alarms are removed after ringing.
- A separate loop, not the Telegram long-poll, does the checking: `getUpdates` blocks for ~50 s, which would make alarms late.
- Ringing: `termux-volume music 15`, then `termux-media-player play <file>` every 8 s for up to **40 times (~5 minutes)** or until `/parar`
  removes the marker file (`~/.tgbot/ring.pid`) and stops the player.
- Time zone: Termux uses Android's time zone. If alarms are an hour off, check it with `date` in Termux and `adb shell getprop persist.sys.timezone`.
  (On a phone without Google Play Services, "automatic time zone" can pick a wrong zone. The author's J4 was in `America/Noronha` instead of
  `America/Sao_Paulo`; fix: `adb shell settings put global auto_time_zone 0; adb shell cmd alarm set-timezone America/Sao_Paulo`.)

## Limits (be aware)

- Precision is ~15 s. The phone must be on, with Termux alive (the wake lock does that; see [12](12-operating-and-battery.md)).
- If the phone is in silent/Do-Not-Disturb mode, the `music` stream may still be muted on some ROMs. Test once.
- Alarms that fall while the phone is off are **not** rung afterwards.
- Recurring alarms are stored in a file, so they should survive a reboot (the file is in `~/.tgbot`; the bot itself was verified to come back after a real reboot, but a recurring alarm firing after one was not).
- No snooze yet (create a one-shot alarm a few minutes later).

## Tests

`tests/test_alarm.sh` extracts the alarm functions from `bot.sh`, stubs Telegram and the Termux commands, and checks parsing
(including the bare `7h` case that was once broken), listing, deletion, "this minute goes to tomorrow", and a real fire of a due one-shot alarm.
