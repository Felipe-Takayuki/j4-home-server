# 14 — A lighter launcher (optional)

After the [debloat](02-debloat.md) the phone needs *some* home screen. [Olauncher](https://github.com/tanujnotes/Olauncher) (F-Droid) is already minimal,
but it still costs **~25 MB of RAM** (Kotlin + AndroidX + view/graphics layers). `launcher/` is a ~170-line, dependency-free replacement
for a phone that is a server and is rarely looked at.

| | Olauncher | `launcher/` (J4 Launcher) |
|---|---|---|
| RAM (`dumpsys meminfo`, TOTAL PSS) | ~25 MB | **~9–11 MB** |
| APK | ~2 MB | **12 KB** |
| Language / deps | Kotlin, AndroidX | Java, only the platform API |

(Measured on the author's J4, Android 10, with a handful of apps installed; the list is rebuilt each time you press Home.)

## What it does

Black screen, clock, date, battery % / charging / temperature, and a plain text list of every launchable app. Tap = open, **long-press = app info**
(uninstall, force stop, permissions). Home again scrolls to the top. Back does nothing.

## Why it is light

- No icons or images at all, programmatic UI (no XML resources), no AndroidX, no Kotlin runtime.
- `android:hardwareAccelerated="false"`: a text list does not need a GPU layer.
- No background receivers or services. The battery is read once on resume; the clock is a framework `TextClock`.
- The app list is built on resume and **dropped on stop**, so nothing sits in RAM while another app is in front.

## Build and install

You need a JDK (11+) and the Android SDK build-tools + one platform (`aapt2`, `d8`, `zipalign`, `apksigner`, `android.jar`); no Gradle.

```sh
launcher/build.sh                                  # -> launcher/out/j4-launcher.apk (signed with a throwaway key in ~/.android/)
adb install -r launcher/out/j4-launcher.apk
adb shell cmd package set-home-activity com.j4.launcher/.MainActivity
```

The key stays on your machine (never commit it); the same key is needed to update the app later. `ANDROID_HOME`, `BUILD_TOOLS`, `ANDROID_JAR`, `KEYSTORE` override the defaults.

## Go back

Install any other launcher (e.g. Olauncher from F-Droid, or `adb install` its APK), then:

```sh
adb shell cmd package set-home-activity <package>/<activity>   # e.g. app.olauncher/.MainActivity
adb uninstall com.j4.launcher
```

If this launcher is the **only** one on the phone (the author removed Olauncher and the Samsung launcher) and it ever breaks, you have no home screen:
Termux, the bot and the web UI keep working, and you can `adb install` a launcher again. Keep the APK (`launcher/build.sh` rebuilds it) handy.

## Not verified

Tested only on the author's J4 (Android 10, 360×640). The 12-hour/24-hour clock is forced to 24 h, and the date is in Portuguese (edit `MainActivity.java`).
