# 15 — Text reminders (`/lembrar`)

A reminder is a **Telegram message at a time you choose**: no sound, no screen. (For something that must wake you up, use the [alarm clock](09-alarm-clock.md).)
It lives inside the bot: one more 15-second background loop, no new process to install, ~0 MB of extra RAM.

## Commands

| Message | Meaning |
|---|---|
| `/lembrar em 30min tirar a roupa` | in 30 minutes (`45m`, `2h`, `1h30`, `2d`) |
| `/lembrar 18h ligar pro João` | today at 18:00, or tomorrow if that time has passed (`18:30`, `18h30`) |
| `/lembrar amanhã 9h pagar a luz` | tomorrow 09:00 (`hoje`, `amanhã`) |
| `/lembrar sexta 9h reunião` | the *next* Friday (`segunda` … `domingo`) |
| `/lembrar 25/12 comprar presente` | on that date at 09:00 (the default time); `25/12 18h` sets the time; `25/12/2027` pins the year |
| `/lembrar diario 8h tomar remédio` | every day (`todo dia`); `semana` = Mon–Fri; `fds` = Sat–Sun |
| `/lembrar lista` | lists them (`/lembretes` also works) |
| `/lembrar apagar N` · `/lembrar apagar todos` | deletes one or all |

The words before the text (date, time, `diario`…) are read first; **everything after them is the message**. A word like `9` or `semana` that comes *after*
the time is just text, so `/lembrar 18h comprar 9 ovos` works.

## Details worth knowing

- **Late is better than never.** If the phone or bot was down when a reminder was due, it is delivered as soon as the bot is back, with a note saying when it was meant for.
- **A failed send is retried.** The reminder is only removed after Telegram confirms the message (`sendMessage` returned `ok`), so a Wi-Fi drop does not lose it.
- A one-shot reminder in the past is rejected; an impossible date (`31/02`) is rejected.
- A date with only a day/month that already passed this year means next year. Weekday names always mean the *next* one, never today.
- The text can be up to 500 characters and may contain `|`.

## Storage

`~/.tgbot/reminders`, one line per reminder (the text is last, so it can contain `|`):

```
id|epoch|once||text                      one-shot (epoch = Unix time)
id|HH:MM|daily|last_day|text             recurring (daily | weekdays | weekend)
```

It is plain text: you can edit it over SSH. The phone's clock and time zone are used (see [11](11-android10-pitfalls.md) if the clock is off).

## Tested

`tests/test_reminders.sh` (run by `make test`) covers parsing of every form above, rejections, listing/deleting, firing, late delivery and the retry on a failed send, with Telegram stubbed.
Not tested: day-long recurring reminders across a real midnight, and behaviour on devices other than the author's J4.
