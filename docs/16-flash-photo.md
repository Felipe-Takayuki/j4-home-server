# 16 — Photos with flash (`/foto flash`)

`termux-camera-photo` cannot use the flash, and the torch trick does not work either (see [11](11-android10-pitfalls.md#no-flash-with-termux-camera-photo)):
Android switches the torch off the moment another client opens the camera. So this repo ships a tiny app, **J4 FlashCam** (`flashcam/`, 17 KB, Java, no
dependencies), that drives the camera itself: the *same* Camera2 session that exposes the sensor also holds the LED lit (`FLASH_MODE_TORCH`), so the scene is really lit.

|  | `/foto` | `/foto flash` |
|---|---|---|
| Camera | rear or front (`/foto frente`) | rear only (the front has no flash) |
| Screen | stays off | **wakes for ~3–5 s** (Android 10 only lets a *visible* app use the camera) |
| Needs | Termux:API | the FlashCam app (below) |

Measured on the author's J4 in a dark room (EXIF): without flash 1/17 s, ISO 1990, brightness value −2.2; with FlashCam 1/40 s, ISO 350, +1.6, and the shadow a point light casts is visible.

## Photos are never saved

The photo is built **in memory** inside the app (an `ImageReader` buffer): FlashCam has no storage permission and writes no file. It sends the bytes to the bot over
`127.0.0.1` (never the network), and the bot hands them to Telegram and deletes its temporary copy right away. The bot also deletes any leftover temp photo at start-up,
and the test suite checks that nothing is left behind after success, errors and timeouts.

## Install (from the PC, phone connected over `adb`)

```sh
flashcam/install.sh
```

It builds the APK (`flashcam/build.sh`, needs a JDK and the Android SDK build-tools), installs it, grants the `CAMERA` permission, and allows Termux to
"display over other apps" (`appops set com.termux SYSTEM_ALERT_WINDOW allow`). That last grant matters: Android 10 forbids background apps from starting activities,
and the bot runs inside Termux, in the background, usually with the screen off.

Then update the bot (`tools/adb-run.sh install/tgbot.sh`) and send `/foto flash`.

## How it works

1. The bot picks a random port and a random one-time key, starts a one-shot receiver on `127.0.0.1:<port>` (it only accepts a POST to `/<key>`), and runs
   `am start -n com.j4.flashcam/.FlashActivity --ei port <port> --es key <key>`.
2. The activity turns the screen on, opens the rear camera, lights the LED, waits ~1.5 s for exposure/focus to settle on the lit scene, takes one JPEG (≤ 5 MP) and POSTs it
   to the receiver with `X-Result: ok`. On any problem it POSTs `X-Result: erro` with the reason, which the bot forwards to you. It gives up after 20 s.
3. The activity closes (the torch goes off with the camera), the bot sends the photo to Telegram and deletes it. The screen then times out on its own.

## Limits and caveats

- Rear camera only; the LED is a torch (steady light), not a strobe, so it is dimmer than a phone-camera flash but the exposure adapts to it.
- The screen lights up for a few seconds on every `/foto flash`: not for discreet use.
- It needs the camera to be free (another app using it makes the request fail with a message).
- Test without Telegram in the loop on the phone: `bash ~/.tgbot/bot.sh --foto flash` (the photo still goes to your Telegram).
- Verified end to end on the author's J4: triggered from Termux with the screen off, the photo arrived in Telegram.
- Tested only on the author's J4 (Android 10). Other devices may differ in sizes, focus and how long the torch needs to settle.
