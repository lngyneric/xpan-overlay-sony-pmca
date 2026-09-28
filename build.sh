#!/bin/bash
# Build XPanOverlay PMCA app (standard Android APK, API 10 compatible)
# Produces: XPanOverlay-1.0.apk  (install via pmca-gui / pmca-console)

set -e
cd "$(dirname "$0")"

SDK=/home/user/android-sdk
BT=$SDK/build-tools/25.0.3
ANDROID_JAR=$SDK/platforms/android-10/android.jar
JAVAC=/home/user/jdk17/bin/javac
JAVA_HOME=/home/user/jdk17

OUT=build
rm -rf "$OUT"
mkdir -p "$OUT/classes"

echo "[1/6] aapt: compile manifest -> base.apk"
"$BT/aapt" package -f -M AndroidManifest.xml -I "$ANDROID_JAR" -F "$OUT/base.apk"

echo "[2/6] javac: compile java sources (target 1.7)"
find src -name '*.java' > "$OUT/sources.txt"
"$JAVAC" -source 1.7 -target 1.7 \
    -classpath "$ANDROID_JAR" \
    -d "$OUT/classes" @"$OUT/sources.txt" 2>&1 | grep -v "bootstrap class path" || true

echo "[3/6] dx: dex (min-sdk 10 -> dex 035)"
JAVA_HOME="$JAVA_HOME" "$BT/dx" --dex --output="$OUT/classes.dex" "$OUT/classes"

echo "[4/6] zip: add classes.dex to base.apk"
( cd "$OUT" && zip -q base.apk classes.dex )

echo "[5/6] zipalign"
"$BT/zipalign" -f 4 "$OUT/base.apk" "$OUT/aligned.apk"

echo "[6/6] apksigner (v1+v2)"
if [ ! -f debug.keystore ]; then
    /home/user/jdk17/bin/keytool -genkeypair -keystore debug.keystore \
        -alias xpan -storepass xpan1234 -keypass xpan1234 \
        -dname "CN=XPanOverlay" -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
fi
"$BT/apksigner" sign --ks debug.keystore \
    --ks-pass pass:xpan1234 --key-pass pass:xpan1234 \
    --min-sdk-version 10 \
    --out "$OUT/XPanOverlay-1.0.apk" "$OUT/aligned.apk"

echo "DONE: $OUT/XPanOverlay-1.0.apk"
