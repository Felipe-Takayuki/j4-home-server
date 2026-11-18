# 11 — Android 10 pitfalls (the valuable part)

Everything in this page cost real time. If you build something on an old Android phone, read this before you pick software.

## 1. `SIGSYS` — the seccomp trap (the big one)

Android's seccomp filter for apps is older than the libc/Go runtimes that run in them. On this device (Android 10) a process is **killed with `SIGSYS`**
the moment it calls **`statx`** or **`faccessat2`**.

| Victim | Symptom | Fix |
|---|---|---|
| FileBrowser Quantum (v1 and v2, modernc SQLite) | crashes on `statx` | not usable; chose dufs |
| Official `tailscaled` | crashed on `faccessat2` | run it with an **empty directory as `PATH`** (Go's `exec.LookPath` calls `faccessat2` for every `PATH` entry) |
| The `tailscale` CLI | dies with SIGSYS if `PATH` contains directories with executables | the `ts` wrapper sets an empty `PATH` and the socket |
| Any Go program that execs something | same | empty `PATH` dir + **absolute paths** for everything it runs |

**Native Termux packages are fine** (they use Android's bionic libc): `dufs`, `openssh`, `python`, `curl`. Prefer them over generic Linux binaries. Go binaries,
Rust musl builds and anything that uses a newer libc are the risky ones. When a program disappears with "Bad system call", suspect this.

## 2. Termux's package index is old

- `apt` could not find `dnsmasq`; `pkg install ffmpeg` fails (a `libc++` symbol is missing) unless *everything* is upgraded.
- Do **not** run `pkg upgrade` casually. Prefer Python's standard library or a static binary you control.
- Termux cannot read `/proc/uptime`, `/proc/stat`, `/proc/loadavg` (SELinux): use `uptime -p`, `/proc/meminfo`.
- No `getent`, no `nc`.
- Termux **cannot bind ports below 1024** (no DNS on 53, no HTTP on 80). Use high ports and let `tailscale serve` front them.

## 3. Process-management gotchas

- `pgrep -x tailscaled` is unreliable; use `pgrep -f /usr/bin/tailscaled`. `pgrep -x sshd` works.
- `pgrep -f` and `pkill -f` match **their own command line** when the pattern is a literal string typed into a shell: use `pkill -f '[.]tgbot/bot[.]sh'`.
  On the PC the same bites you if you run `pkill -f` from a script that contains the pattern; track PIDs instead.
- Boot scripts have a minimal environment: absolute paths, and call `termux-wake-lock` first.

## 4. Debloat

- Removing packages and **rebooting immediately loses the change**: wait ~30 s.
- Samsung re-enables `com.samsung.android.game.gos` at every boot (uninstall and disable both revert). Harmless.
- After a reboot the phone once came back with USB debugging off / `adb` unauthorized. Services kept running.
- With the Samsung keyboard removed, `adb shell input text` still works (it injects text), which is how scripts talk to Termux ([13](13-deploying-from-a-pc.md)).

## 5. Android Private DNS vs MagicDNS (DNS ad blocker)

- Private DNS **replaces** the VPN's DNS (Tailscale MagicDNS), so tailnet names stop resolving unless the Private DNS server resolves them itself
  (`dnsblock.py` does).
- The "couldn't access private DNS server" warning on the plain Wi-Fi screen is a validation message about the underlying network; if pages load, ignore it.
- Strict hostname mode + Tailscale off (or server down) = no name resolution at all.
See [10](10-dns-adblocker.md).

## 6. dufs and the proxy

- dufs serves the custom UI from memory: restart it after changing `index.html`.
- `HEAD /missing/` returns **200** (the UI), `HEAD /missing` returns 404: existence checks must not use a trailing slash.
- A large unauthenticated `PUT` through `tailscale serve` returns **502**, not 401, so the UI sends `Authorization` itself.
- Plain `curl` gets a text listing; send browser-like headers to test the UI ([06](06-dufs-cloud.md)).

## 7. Termux:API and the camera

- `termux-camera-photo` works with the screen **off**, with only the `CAMERA` runtime permission granted to Termux:API.
- Typing into Termux through `adb shell input text`: wake the screen, wait ~3 s, **tap the terminal first**, or the first characters are lost.
  A backslash-escaped space is typed literally; keep commands short and fetch scripts instead ([13](13-deploying-from-a-pc.md)).

## 8. Time zone without Google services

"Automatic time zone" can choose a wrong zone on a phone without Play Services (the author's was one hour ahead). Set it explicitly:
`adb shell settings put global auto_time_zone 0; adb shell cmd alarm set-timezone <Area/City>`.

## 9. Memory budget (measured)

With everything of this project running on a 1.84 GB phone: ~910 MB used, **~930–975 MB available**. The floor is system_server (~200 MB), SystemUI (~75 MB)
and the phone stack (~50 MB). The phone already has ~1.5 GB of zram swap. Heavy things (Node apps, Java, Jellyfin, Nextcloud, Home Assistant) are out of budget.

## 10. Quirks in tools you may reach for

- Original **File Browser** is archived (no security fixes); FileBrowser Quantum crashes here (section 1).
- `tailscale serve` is additive: a new `--https`/`--tcp` port keeps the others; `ts serve reset` wipes all.

## No flash with `termux-camera-photo`

`termux-camera-photo` has no flash option, and the obvious workaround does not work: `termux-torch on` followed by a photo (torch lit before the camera opens, or lit
0.3–1.5 s after it opens) gives a photo with **identical exposure** to one without it (1/17 s, ISO ~1990 in a dark room, both ways), because Android switches the torch off
the moment a camera client opens the device. The photos are not lit. A real flash needs an app that drives the camera itself (Camera2 with a flash mode); nothing in this repo does that yet.
