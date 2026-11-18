# J4 Home Server

Turn an old, locked-down Android phone into a small **private home server** — a personal cloud,
an ad-blocking DNS resolver and a Telegram remote control — using only [Termux](https://termux.dev),
[Tailscale](https://tailscale.com) and a few hundred lines of shell and Python.
**No root, no unlocked bootloader, no open ports.**

It was built on a Samsung Galaxy J4 (SM-J400M: Android 10, 32-bit ARM, 1.8 GB RAM, no SD card), which is about
as hostile as a server gets, so it should run on most spare phones that are better than that.
Most of the repository is not the code itself but the **list of things that break on old Android and how
they were worked around** ([docs/11](docs/11-android10-pitfalls.md)).

> 🇧🇷 Leia em português: [README.pt-BR.md](README.pt-BR.md). The bot's chat messages and most code comments are in Brazilian
> Portuguese; the documentation is in English. Translations of the bot are welcome (see [CONTRIBUTING](CONTRIBUTING.md)).

## What you get

| Piece | What it does | Docs |
|---|---|---|
| **Debloat** | Removes Google/Samsung/carrier apps for user 0 with `adb` (reversible) so the whole stack fits in about 910 MB of the 1.84 GB | [02](docs/02-debloat.md) |
| **Termux + autostart** | Everything starts at boot with Termux:Boot and a wake lock | [03](docs/03-termux.md), [04](docs/04-ssh-and-autostart.md) |
| **Tailscale** | Private network + HTTPS certificates, in userspace mode (no VPN slot, no root) | [05](docs/05-tailscale.md) |
| **Cloud** | [dufs](https://github.com/sigoden/dufs) file server (WebDAV, search, zip) behind `tailscale serve` | [06](docs/06-dufs-cloud.md) |
| **Web UI** | A single-file responsive UI for dufs: grid/list, video/image viewer, drag-and-drop folders, rename/move, storage panel, dark/light | [07](docs/07-web-ui.md) |
| **Telegram bot** | `/status`, `/foto` (camera), `/tocar` (play a sound), `/despertador`, `/dns`, `/parar` — answers only to you | [08](docs/08-telegram-bot.md) |
| **Reminders** | Text reminders by Telegram: `/lembrar amanhã 9h pagar a luz`, `em 30min`, `25/12`, `diario 8h`; delivered late rather than lost | [15](docs/15-reminders.md) |
| **Alarm clock** | Set alarms from Telegram; the phone rings until you send `/parar` | [09](docs/09-alarm-clock.md) |
| **DNS ad blocker** | ~76k-domain blocklist served as DNS-over-TLS on your tailnet for Android's *Private DNS*, with a watchdog | [10](docs/10-dns-adblocker.md) |
| **Light launcher** | Optional 12 KB text-only home screen (~10 MB RAM vs ~25 MB for Olauncher), built with plain SDK tools | [14](docs/14-light-launcher.md) |
| **Tooling** | Run scripts inside Termux from the PC over `adb` (no SSH needed), offline tests, CI | [13](docs/13-deploying-from-a-pc.md) |

```
                       your devices (phone, tablet, PC) — all on your Tailscale tailnet
                                     │ WireGuard (Tailscale)
 ┌───────────────────────────────────▼────────────────────────────────────┐
 │ old Android phone (Termux, no root)                                    │
 │                                                                        │
 │  tailscaled (userspace) ──serve──► :443  HTTPS ──► dufs 127.0.0.1:8080 │  → the "cloud" + web UI
 │                          └─serve─► :853  TLS   ──► dnsblock :5353      │  → ad-blocking DNS (Private DNS)
 │  sshd :8022 (key only)                                                 │
 │  bot.sh ──► Telegram Bot API (outbound only) ──► /status /foto /dns …  │
 └────────────────────────────────────────────────────────────────────────┘
        nothing listens on the LAN or the internet; Tailscale is the only way in
```

## Quick start

You need a PC with `adb`, an Android phone with USB debugging, a free Tailscale account, and a Telegram bot token
if you want the bot. Details and every gotcha are in the numbered docs; the short version:

1. [Prepare the phone](docs/01-prepare-the-phone.md) (USB debugging, F-Droid, Termux, Termux:Boot, Termux:API).
2. *(optional, aggressive)* [Debloat](docs/02-debloat.md): `debloat/debloat.sh --dry-run`, read the list, then run it.
3. [Termux packages and boot scripts](docs/03-termux.md), [SSH](docs/04-ssh-and-autostart.md), [Tailscale](docs/05-tailscale.md).
4. Install the pieces you want from the PC (the phone must be awake):
   ```sh
   tools/adb-run.sh install/cloud.sh      # dufs + web UI (prints a random password once, on the phone screen)
   tools/adb-run.sh install/tgbot.sh      # Telegram bot (create ~/.tgbot/config first, see docs/08)
   tools/adb-run.sh install/dnsblock.sh   # DNS ad blocker (+ tailscale serve on :853)
   ```
5. Run the offline tests any time: `make test` (or `./tests/run.sh`).

## Status — what has and has not been verified

This is a personal project that works on **one device** (the author's J4). Be honest with yourself about that.

- **Verified on the device:** cloud + UI over Tailscale HTTPS, SSH, bot commands used daily (alarm firing, `/parar`,
  alerts), DNS blocking from two Android phones through Private DNS, tailnet-name resolution fix, the watchdog's down/up alerts.
- **Covered by automated tests (no phone needed):** the DNS server (list parsing, matching, packet building, UDP/TCP/DoT framing,
  tailnet answers) and the alarm logic (parsing, scheduling, firing). See [tests/](tests/).
- **Not verified:** a full reboot of the phone bringing every service back by itself; `install/cloud.sh` on a clean
  device (the other two installers were exercised on the real one); other phone models and Android versions.

## Security in one paragraph

Services bind to `127.0.0.1` and are exposed **only** to your tailnet via `tailscale serve`; the bot ignores everyone but
your Telegram user id; SSH is key-only. An Android 10 phone no longer receives security patches, so **never** put it on the
public internet (no port forwarding, no `tailscale funnel`). Read [SECURITY.md](SECURITY.md) before you start.

## Credits and licenses

Built on great software: [Termux](https://termux.dev), [Tailscale](https://tailscale.com), [dufs](https://github.com/sigoden/dufs),
[Telegram Bot API](https://core.telegram.org/bots/api). The ad blocker downloads [StevenBlack/hosts](https://github.com/StevenBlack/hosts)
(MIT) at runtime; it is not bundled. This repository is under the [MIT License](LICENSE).
