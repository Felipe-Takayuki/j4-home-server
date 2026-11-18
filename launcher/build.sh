#!/usr/bin/env bash
# Builds launcher/out/j4-launcher.apk with plain SDK tools (no Gradle, no Kotlin, no AndroidX).
# Needs: javac (JDK 11+), and an Android SDK with build-tools and a platform (aapt2, d8, zipalign, apksigner).
set -euo pipefail
cd "$(dirname "$0")"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/android-sdk}}"
BT="${BUILD_TOOLS:-$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)}"
JAR="${ANDROID_JAR:-$(ls -d "$SDK"/platforms/android-*/android.jar | sort -V | tail -1)}"
OUT=out
KEY="${KEYSTORE:-$HOME/.android/j4-launcher.keystore}"

rm -rf "$OUT"; mkdir -p "$OUT/classes"

"$BT/aapt2" link -o "$OUT/base.apk" -I "$JAR" --manifest AndroidManifest.xml \
    --min-sdk-version 21 --target-sdk-version 29
javac -source 8 -target 8 -Xlint:-options -cp "$JAR" -d "$OUT/classes" src/com/j4/launcher/*.java
"$BT/d8" --release --min-api 21 --lib "$JAR" --output "$OUT" $(find "$OUT/classes" -name '*.class')
( cd "$OUT" && zip -q -j base.apk classes.dex )
"$BT/zipalign" -f 4 "$OUT/base.apk" "$OUT/aligned.apk"

if [ ! -f "$KEY" ]; then   # personal throwaway key, kept outside the repo
    mkdir -p "$(dirname "$KEY")"
    keytool -genkeypair -keystore "$KEY" -storepass j4launcher -keypass j4launcher \
        -alias j4 -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=J4 Launcher" >/dev/null
fi
"$BT/apksigner" sign --ks "$KEY" --ks-pass pass:j4launcher --key-pass pass:j4launcher \
    --out "$OUT/j4-launcher.apk" "$OUT/aligned.apk"
rm -f "$OUT/base.apk" "$OUT/aligned.apk"
ls -l "$OUT/j4-launcher.apk"
