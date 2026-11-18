# 12 — Operating the server (and keeping the battery alive)

## Checklist for a healthy phone-server

- Termux, Termux:Boot, Termux:API (and Tailscale if you use its app) are **battery-unrestricted**.
- `termux-wake-lock` is held (the boot scripts do it); Android shows Termux's persistent notification while it is.
- Free RAM stays above ~500 MB (`/status` shows it).
- The bot's `/status` shows `sshd`, `dufs`, `tailscaled` (and `dns`, if the ad blocker is installed) as ✅.
- `/dns` shows the ad blocker active (if installed).

## The battery problem (read this)

A phone kept on a charger 24/7 sits at 100 % and ~4.3 V, which wears a lithium-ion cell and, over months or years, can **swell** it. This is the real hardware
risk of the whole idea. On the author's device:

- `dumpsys battery` shows `status: 5` (FULL): the charger stops pushing current at 100 % and tops up only when the level drops a few percent.
- There is **no battery-limit option**: Android 10 / One UI 2 has no "protect battery (85 %)"; Samsung's Device Care is not installed; the sysfs nodes that
  would cap charging (`batt_slate_mode`, `store_mode`) are root-only and the bootloader is locked.

What you can do:

1. **Smart plug / timer** driven by the battery level: charge at ~40 %, cut at ~80 %. A mechanical timer works too. A script can read the level with
   `termux-battery-status` or `dumpsys battery`, and a plug with a local API (Tasmota, Shelly) can be switched with `curl`. *(Not implemented here.)*
2. A **weak charger** (5 V / 1 A) instead of a fast one, in a cool place.
3. **Watch it:** `/status` flags temperature ≥ 40 °C and low battery while unplugged. Look at the back cover now and then; if it bulges, stop using the battery.
4. Treat the phone as a *helper*, not the only home of important data: it is old hardware with a worn battery, so keep a second copy of anything you care about.

## Stay-awake and the screen

`stay_on_while_plugged_in` keeps the screen on while charging. It makes the phone easy to drive over `adb` but wears the display and adds heat.
Turn it off (`adb shell settings put global stay_on_while_plugged_in 0`) once everything is installed; the services keep running with the screen off.

## Restarting things

```sh
sh ~/.termux/boot/30-cloud      # dufs      (pkill dufs first to reload the UI)
sh ~/.termux/boot/50-tgbot      # bot       (pkill -f '[.]tgbot/bot[.]sh' makes the supervisor restart it)
sh ~/.termux/boot/60-dnsblock   # ad blocker
ts-start                        # tailscaled
```

## Updating

Re-run the matching installer from the PC (`tools/adb-run.sh install/<x>.sh`). They back up what they replace (`bot.sh.bak`), validate syntax before swapping files, and
restart only the affected service.

## Unverified: reboot

A full reboot should bring everything back (boot scripts are numbered and idempotent), but this was **not verified** end to end. After you reboot your phone for the first time,
check `/status`, `/dns` and open the cloud; then tell the project (issue or PR to this page) how it went.
