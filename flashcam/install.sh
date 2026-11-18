#!/usr/bin/env bash
# Run on the PC with the phone connected over adb. Builds (if needed), installs the app, and grants what it needs.
set -euo pipefail
cd "$(dirname "$0")"
[ -f out/j4-flashcam.apk ] || ./build.sh
adb install -r out/j4-flashcam.apk
adb shell pm grant com.j4.flashcam android.permission.CAMERA
# Android 10 does not let a background app start an activity. Termux (where the bot runs) must be allowed
# to "display over other apps" for `am start` from the bot to work while the screen is off.
adb shell appops set com.termux SYSTEM_ALERT_WINDOW allow
echo "FlashCam installed. Test from the phone's Termux: am start -n com.j4.flashcam/.FlashActivity --ei port 1 --es key x"
