# 13 — Deploying from a PC without SSH

The phone has no browser and the on-screen keyboard is painful, so how do you get files in and commands run? Two ways.

## A. `tools/adb-run.sh` (works from the very first minute)

```sh
tools/adb-run.sh install/dnsblock.sh
```

1. Starts `python3 -m http.server` on `127.0.0.1:$PORT` serving **this repository** (default port 8765; it refuses to start if the port is busy).
2. `adb reverse tcp:$PORT tcp:$PORT` makes that port reachable on the phone as `localhost:$PORT`.
3. Brings Termux to the foreground, wakes the screen, taps the terminal and types, with `adb shell input text`:
   `curl -s http://localhost:8765/install/dnsblock.sh | BASE=http://localhost:8765 bash`.
4. Keeps the server up for `WAIT` seconds (default 90), then cleans up (`adb reverse --remove`, kills the server).

The installer scripts download the files they need from `$BASE`, so **only repository files ever travel this way, and only over the USB cable's loopback**.
Secrets (bot token, dufs password) are never part of it — type those on the phone or over SSH.

Environment knobs: `PORT`, `TAP_X`/`TAP_Y` (screen coordinates that focus the terminal; defaults assume a 360×640 screen), `WAIT`.

### Lessons baked into the script

- `input text` is **lossy right after the screen wakes**: wake, wait ~3 s, **tap the terminal**, then type.
- `input text` treats `\ ` literally and `|`/`&` specially: that is why the typed command is short and fetches a script instead of being a long one-liner. Pass `%s` for a space if you must.
- Use a **port that is free on your PC**. (A forgotten dev server on `:8000` once answered the phone with its own 404 page instead of the script.)
- Output from phone scripts can be sent back by `curl -X POST --data-binary @file http://localhost:$PORT/name`, if you run a server that accepts POST, but reading the phone's
  screen with `adb exec-out screencap -p > shot.png` is often enough.

## B. SSH over Tailscale (once [04](04-ssh-and-autostart.md) and [05](05-tailscale.md) are done)

```sh
ssh -p 8022 <termux-user>@j4.<your-tailnet>.ts.net
scp -P 8022 tgbot/bot.sh <termux-user>@j4.<your-tailnet>.ts.net:.tgbot/bot.sh
```

Nicer for interactive work and for secrets, since nothing has to be typed through `adb`.

## Testing without the phone

```sh
make test      # = ./tests/run.sh : shell/Python syntax, DNS server unit tests, alarm logic tests
```

CI (`.github/workflows/test.yml`) runs the same thing on every push and pull request.
