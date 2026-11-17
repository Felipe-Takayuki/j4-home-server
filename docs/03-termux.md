# 03 — Termux packages and boot scripts

Goal: Termux has the tools every later step needs, and everything starts by itself when the phone boots.

## Packages

Open Termux on the phone (or run these over `adb`/SSH later):

```sh
pkg install openssh dufs python jq curl termux-api procps
```

What each is for: `openssh` (remote shell), `dufs` (the cloud), `python` (DNS blocker), `jq` + `curl` (the bot),
`termux-api` (command-line access to camera/battery/media), `procps` (`pgrep`/`pkill`).

> ⚠️ **Do not run `pkg upgrade` casually, and do not be surprised if a package is "not found".** On the author's device the
> Termux package index was old: `apt` could not even locate `dnsmasq`, and `pkg install ffmpeg` fails with a missing `libc++` symbol unless
> *everything* is upgraded first. The pieces in this repo deliberately depend only on what was already installable (and on Python
> for the DNS server, instead of `dnsmasq`). If you want to upgrade, do it deliberately and expect to fix things. See [11](11-android10-pitfalls.md).

## How autostart works

[Termux:Boot](https://github.com/termux/termux-boot) runs every executable in `~/.termux/boot/` (alphabetical order) when Android boots,
**provided you opened the Termux:Boot app at least once**. This repo ships numbered scripts in [`termux/boot/`](../termux/boot):

| Script | Starts | Installed by |
|---|---|---|
| `10-sshd` | OpenSSH on port 8022 | [04](04-ssh-and-autostart.md) |
| `20-tailscale` | `tailscaled` in userspace mode (`ts-start`) | [05](05-tailscale.md) |
| `30-cloud` | `dufs` | `install/cloud.sh` |
| `40-status` | the disk-usage publisher for the UI | `install/cloud.sh` |
| `50-tgbot` | the Telegram bot supervisor | `install/tgbot.sh` |
| `60-dnsblock` | the DNS ad-blocker supervisor | `install/dnsblock.sh` |

Every script is **idempotent** (it exits if its service is already running) so you can also run it by hand: `sh ~/.termux/boot/30-cloud`.
Each one calls `termux-wake-lock` so the CPU is not put to sleep with the screen off.

For the long-running Python/shell services there is a tiny supervisor loop (`run.sh`) that restarts them 5 seconds after they exit.
No `systemd`, no `runit` — just `while …; do …; sleep 5; done`.

## Ground rules for scripts on this device

- Use **absolute paths** (`/data/data/com.termux/files/usr/bin/...`) in boot scripts: the boot environment has a minimal `PATH`.
- `pgrep -x tailscaled` is unreliable; use `pgrep -f /usr/bin/tailscaled`. In the other direction, `pgrep -f`/`pkill -f` can match their own
  command line: use the `[x]` trick (`pkill -f '[.]tgbot/bot[.]sh'`) so the pattern does not match itself.
- No `getent`, no `nc`. `/proc/uptime`, `/proc/stat` and `/proc/loadavg` are not readable (SELinux): use `uptime -p` and `/proc/meminfo`.

Continue with [04 — SSH and autostart](04-ssh-and-autostart.md).
