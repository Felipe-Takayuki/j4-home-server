# 01 — Prepare the phone

Goal: a phone you can drive from the PC with `adb`, with Termux and its add-ons installed.

## What the author's device looks like

| | |
|---|---|
| Model | Samsung Galaxy J4, SM-J400M (Brazil) |
| Android | 10 (One UI 2), **no longer receives security patches** |
| CPU | 32-bit ARM (`armv7`) — many prebuilt binaries are `arm64`-only, so check before you plan anything |
| RAM | 1.8 GB (+ ~1.5 GB of Samsung zram swap) |
| Storage | ~20 GB free internal, no SD card |
| Root / bootloader | none / locked — and everything here works anyway |

Anything with ≥ 2 GB of RAM and Android 8+ should be at least as comfortable. Android 12+ has its own traps
(the "phantom process killer" can kill Termux children) that this project has not been tested against.

## 1. Enable USB debugging

1. Settings → About phone → Software information → tap **Build number** 7 times.
2. Settings → Developer options → enable **USB debugging**.
3. Plug into the PC, accept the RSA fingerprint prompt on the phone, check:
   ```sh
   adb devices        # should list your phone as "device" (not "unauthorized")
   ```
4. Optional but useful for a server: Developer options → **Stay awake** (screen stays on while charging), and set the screen timeout
   low. A server phone that is always on a charger also keeps its screen on; see [12](12-operating-and-battery.md) for the trade-off.

> After a reboot the author's phone once came back with USB debugging off / `unauthorized`. The services kept working;
> only `adb` was affected. Re-enable it when you need it.

## 2. Install Termux and its add-ons from **F-Droid**

The Play Store build of Termux is abandoned and old. Use F-Droid (or the GitHub releases), and install all add-ons from the **same source**
so their signatures match:

| App | Why |
|---|---|
| **Termux** | the Linux environment |
| **Termux:Boot** | runs scripts from `~/.termux/boot/` when the phone boots (open it once so Android lets it start) |
| **Termux:API** | camera, battery, media player, volume used by the bot. Grant **only** the permissions you need (the bot needs `CAMERA`) |
| *(optional)* a small keyboard such as Simple Keyboard | if you removed the Samsung keyboard in the debloat step |

A phone without Google Play Services has no store, so you either install the APKs with `adb install` or put F-Droid on it first.

## 3. Let Android keep Termux alive

Android's battery manager is the #1 enemy of a home server. For **Termux, Termux:Boot, Termux:API and Tailscale (if you use the app)**:

- Settings → Apps → *app* → Battery → **Unrestricted** (wording varies by vendor).
- Settings → Battery → *Background usage limits* / *Sleeping apps*: make sure none of them is in "sleeping" or "deep sleeping".
- Keep the notification Termux shows while it holds the wake lock (`termux-wake-lock`); it is what keeps the CPU awake. The boot scripts in
  this repo call it.

## 4. Sanity check

```sh
adb shell getprop ro.build.version.release   # Android version
adb shell getprop ro.product.cpu.abi         # armeabi-v7a (32-bit) or arm64-v8a
adb shell cat /proc/meminfo | head -3
```

Open Termux on the phone once, then continue with [02 — Debloat](02-debloat.md) (optional) or straight to [03 — Termux](03-termux.md).
