#!/usr/bin/env bash
#
# Build the XPanOverlay PMCA app.
#
#   output: build/XPanOverlay-<versionName>.apk   (e.g. XPanOverlay-1.2.apk)
#
# Runs on Git Bash / MSYS2 (Windows), WSL, macOS and Linux.
# JDK, Android SDK, build-tools and platform are all auto-detected.
#
# Override anything with env vars:
#   JAVA_HOME       path to a JDK (needs javac + keytool)
#   ANDROID_HOME    path to the Android SDK   (ANDROID_SDK_ROOT also honoured)
#   BT_VERSION      build-tools version, default 25.0.3
#   PLATFORM        platform dir, default android-10
#
# Usage:
#   ./build.sh                 build
#   ./build.sh --bootstrap     download cmdline-tools + platform + build-tools, then build
#   ./build.sh --clean         remove build/ and debug.keystore
#
# Install the result on the camera with pmca-gui / pmca-console.

set -eo pipefail
cd "$(dirname "$0")"

EXE=""
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) EXE=".exe";; esac
IS_WIN=""
[ -n "$EXE" ] && IS_WIN=1

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# "C:\Foo\Bar" or "C:/Foo/Bar" -> "/c/Foo/Bar"
to_posix() {
  local p="${1//\\//}"
  if [[ "$p" =~ ^([A-Za-z]):/(.*)$ ]]; then
    local d="${BASH_REMATCH[1]}"
    d="${d,,}"
    p="/$d/${BASH_REMATCH[2]}"
  fi
  printf '%s' "$p"
}

# "/c/Foo/Bar" -> "C:\Foo\Bar" for native (non-MSYS) child processes
to_native() {
  if [ -n "$IS_WIN" ] && command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

# pick the first existing of <name>.exe / <name>.bat / <name>
pick() {
  local dir="$1" n="$2" c
  for c in "$dir/$n$EXE" "$dir/$n.bat" "$dir/$n"; do
    if [ -f "$c" ]; then printf '%s' "$c"; return; fi
  done
}

BOOTSTRAP=0
for a in "$@"; do
  case "$a" in
    --bootstrap) BOOTSTRAP=1;;
    --clean) rm -rf build debug.keystore; log "cleaned build/ and debug.keystore"; exit 0;;
    -h|--help) sed -n '2,26p' "$0"; exit 0;;
    *) die "unknown option: $a";;
  esac
done

# ---------------------------------------------------------------- version ----
VERSION=$(sed -n 's/.*android:versionName="\([^"]*\)".*/\1/p' AndroidManifest.xml | head -1)
VERSION="${VERSION:-1.2}"
OUT_APK="XPanOverlay-${VERSION}.apk"

# -------------------------------------------------------------------- JDK ----
find_jdk() {
  local c best=""
  local -a cands=()
  [ -n "${JAVA_HOME:-}" ] && cands+=("$(to_posix "$JAVA_HOME")")
  if [ -n "$IS_WIN" ]; then
    cands+=(
      "/c/Program Files/Android/Android Studio/jbr"
      /c/Program\ Files/Java/jdk-*
      /c/Program\ Files/Java/jdk1.*
      /c/Program\ Files/Eclipse\ Adoptium/jdk-*
      /c/Program\ Files/Microsoft/jdk-*
      /c/Program\ Files/Zulu/zulu-*
      /c/Program\ Files/BellSoft/LibericaJDK-*
    )
  else
    cands+=($HOME/jdk* /opt/jdk* /usr/lib/jvm/* /Library/Java/JavaVirtualMachines/*/Contents/Home)
  fi
  for c in "${cands[@]}"; do
    [ -f "$c/bin/javac$EXE" ] || continue
    best="$c"; break
  done
  printf '%s' "$best"
}

JAVA_HOME="$(find_jdk)"
[ -n "$JAVA_HOME" ] || die "no JDK found. Install one and/or set JAVA_HOME (needs javac + keytool).
  Windows: https://adoptium.net  |  Android Studio ships one at C:\\Program Files\\Android\\Android Studio\\jbr"

JAVAC="$JAVA_HOME/bin/javac$EXE"
KEYTOOL="$JAVA_HOME/bin/keytool$EXE"
JARSIGNER="$JAVA_HOME/bin/jarsigner$EXE"
JAVA="$JAVA_HOME/bin/java$EXE"
[ -f "$JAVAC" ] || die "javac not found at $JAVAC"

JAVAC_MAJOR=$("$JAVAC" -version 2>&1 | sed -E 's/^javac ([0-9]+).*/\1/' | head -1)
log "JDK         : $JAVA_HOME (javac $JAVAC_MAJOR)"

# -------------------------------------------------------------------- SDK ----
SDK=""
for s in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}"; do
  if [ -n "$s" ] && [ -d "$(to_posix "$s")" ]; then SDK="$(to_posix "$s")"; break; fi
done
if [ -z "$SDK" ]; then
  for s in "${LOCALAPPDATA:-}/Android/Sdk" "$HOME/AppData/Local/Android/Sdk" \
           "$HOME/Android/Sdk" /c/Android/Sdk /opt/android-sdk /usr/lib/android-sdk; do
    s="$(to_posix "$s")"
    if [ -d "$s" ]; then SDK="$s"; break; fi
  done
fi

if [ -z "$SDK" ] && [ "$BOOTSTRAP" = 1 ]; then
  SDK="$HOME/Android/Sdk"
  [ -n "$IS_WIN" ] && SDK="$HOME/AppData/Local/Android/Sdk"
  log "no SDK found, bootstrapping into $SDK"
  mkdir -p "$SDK"
fi
[ -n "$SDK" ] || die "no Android SDK found. Set ANDROID_HOME, or run: ./build.sh --bootstrap"
[ -d "$SDK" ] || die "Android SDK dir does not exist: $SDK"
log "SDK         : $SDK"

# --------------------------------------------------------------- bootstrap ----
if [ "$BOOTSTRAP" = 1 ]; then
  CMDLINE="$SDK/cmdline-tools/latest"
  if [ ! -f "$CMDLINE/bin/sdkmanager$EXE" ] && [ ! -f "$CMDLINE/bin/sdkmanager.bat" ]; then
    [ "$JAVAC_MAJOR" -ge 17 ] 2>/dev/null || die "--bootstrap needs JDK 17+ (current: $JAVAC_MAJOR). Point JAVA_HOME at a 17+ JDK."
    ZIP="$SDK/cmdline-tools.zip"
    mkdir -p "$SDK/cmdline-tools"
    URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
    [ -n "$IS_WIN" ] && URL="https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
    log "downloading Android cmdline-tools"
    curl -fL --retry 3 -o "$ZIP" "$URL"
    log "extracting to $CMDLINE"
    command -v unzip >/dev/null 2>&1 || die "unzip is required for --bootstrap"
    rm -rf "$CMDLINE"
    unzip -q "$ZIP" -d "$SDK/cmdline-tools"
    [ -d "$SDK/cmdline-tools/cmdline-tools" ] && mv "$SDK/cmdline-tools/cmdline-tools" "$CMDLINE"
    rm -f "$ZIP"
  fi
  SDKMGR="$CMDLINE/bin/sdkmanager"
  [ -n "$IS_WIN" ] && SDKMGR="$CMDLINE/bin/sdkmanager.bat"
  log "installing platform + build-tools (accepting licenses)"
  yes | JAVA_HOME="$(to_native "$JAVA_HOME")" "$SDKMGR" --sdk_root="$(to_native "$SDK")" --licenses >/dev/null 2>&1 || true
  JAVA_HOME="$(to_native "$JAVA_HOME")" "$SDKMGR" --sdk_root="$(to_native "$SDK")" \
      "platforms;${PLATFORM:-android-10}" "build-tools;${BT_VERSION:-25.0.3}" "platform-tools" \
    || warn "sdkmanager refused android-10 / 25.0.3; continuing with whatever it installed"
fi

# ------------------------------------------------------------- build-tools ----
BT_DIR=""
if [ -n "${BT_VERSION:-}" ] && [ -d "$SDK/build-tools/$BT_VERSION" ]; then
  BT_DIR="$SDK/build-tools/$BT_VERSION"
else
  # lowest installed version is most likely to still ship aapt v1 / dx
  for d in $(ls -1d "$SDK"/build-tools/* 2>/dev/null | sort -V); do
    if [ -f "$d/aapt$EXE" ] || [ -f "$d/aapt" ]; then BT_DIR="$d"; break; fi
  done
fi
[ -n "$BT_DIR" ] || die "no usable build-tools in $SDK/build-tools (need one containing aapt).
  Try: sdkmanager \"build-tools;25.0.3\"   or   ./build.sh --bootstrap"
log "build-tools : $(basename "$BT_DIR")"

# ---------------------------------------------------------------- platform ----
PLAT=""
if [ -n "${PLATFORM:-}" ] && [ -f "$SDK/platforms/$PLATFORM/android.jar" ]; then
  PLAT="$SDK/platforms/$PLATFORM"
elif [ -f "$SDK/platforms/android-10/android.jar" ]; then
  PLAT="$SDK/platforms/android-10"
else
  for d in $(ls -1d "$SDK"/platforms/android-* 2>/dev/null | sort -V); do
    if [ -f "$d/android.jar" ]; then PLAT="$d"; break; fi
  done
fi
[ -n "$PLAT" ] || die "no Android platform with android.jar in $SDK/platforms"
ANDROID_JAR="$PLAT/android.jar"
log "platform    : $(basename "$PLAT")"

AAPT="$(pick "$BT_DIR" aapt)"
ZIPALIGN="$(pick "$BT_DIR" zipalign)"
[ -n "$AAPT" ]     || die "aapt not found in $BT_DIR"
[ -n "$ZIPALIGN" ] || die "zipalign not found in $BT_DIR"
DX_JAR="$BT_DIR/lib/dx.jar"
APKSIGNER_JAR="$BT_DIR/lib/apksigner.jar"

# d8 lives only in build-tools 26+; borrow it from any installed version.
# dx (build-tools <= 30) chokes on anything newer than Java 7 bytecode (v51).
D8_JAR=""
for d in $(ls -1d "$SDK"/build-tools/* 2>/dev/null | sort -Vr); do
  if [ -f "$d/lib/d8.jar" ]; then D8_JAR="$d/lib/d8.jar"; break; fi
done
if [ ! -f "$DX_JAR" ] && [ -z "$D8_JAR" ]; then
  die "neither dx.jar nor d8.jar found under $SDK/build-tools/*/lib"
fi
if [ -n "$D8_JAR" ]; then
  DEX_TOOL="d8"; DEX_LEVEL=8
else
  DEX_TOOL="dx"; DEX_LEVEL=7
fi

# ------------------------------------------------------------------- build ----
BUILD=build
rm -rf "$BUILD"
mkdir -p "$BUILD/classes"

log "[1/6] aapt: package manifest -> base.apk"
"$AAPT" package -f -M "$(to_native AndroidManifest.xml)" \
  -I "$(to_native "$ANDROID_JAR")" -F "$(to_native "$BUILD/base.apk")"

log "[2/6] javac: compile sources (dexer: $DEX_TOOL, bytecode: Java $DEX_LEVEL)"
# Windows javac defaults to the GBK codepage; the sources are UTF-8
if [ "${JAVAC_MAJOR:-1}" -ge 20 ] 2>/dev/null && [ "$DEX_LEVEL" = 7 ]; then
  die "dx cannot read Java 8+ bytecode and JDK $JAVAC_MAJOR cannot emit Java 7 bytecode.
  Install build-tools 26+ (for d8): sdkmanager \"build-tools;30.0.3\", or use JDK 8-19."
fi
if [ "${JAVAC_MAJOR:-1}" -ge 9 ] 2>/dev/null; then
  JAVAC_OPTS=(--release "$DEX_LEVEL" -encoding UTF-8)
else
  JAVAC_OPTS=(-source 1.7 -target 1.7 -encoding UTF-8)
fi
"$JAVAC" "${JAVAC_OPTS[@]}" -nowarn \
  -classpath "$(to_native "$ANDROID_JAR")" \
  -sourcepath "$(to_native src)" \
  -d "$(to_native "$BUILD/classes")" \
  "$(to_native src/com/example/xpanoverlay/MainActivity.java)" \
  "$(to_native src/com/example/xpanoverlay/OverlayView.java)"

log "[3/6] dex (min-sdk 10 -> dex 035)"
if [ "$DEX_TOOL" = d8 ]; then
  if ! "$JAVA" -jar "$(to_native "$D8_JAR")" --min-api 10 --lib "$(to_native "$ANDROID_JAR")" \
       --output "$(to_native "$BUILD")" "$(to_native "$BUILD/classes")" 2>"$BUILD/dex.log"; then
    cat "$BUILD/dex.log" >&2
    die "d8 failed"
  fi
else
  if ! "$JAVA" -jar "$(to_native "$DX_JAR")" --dex --output="$(to_native "$BUILD/classes.dex")" \
       "$(to_native "$BUILD/classes")" 2>"$BUILD/dex.log"; then
    cat "$BUILD/dex.log" >&2
    die "dx failed"
  fi
fi
[ -f "$BUILD/classes.dex" ] || die "classes.dex was not produced"

log "[4/6] zip: add classes.dex to base.apk"
if command -v zip >/dev/null 2>&1; then
  ( cd "$BUILD" && zip -q base.apk classes.dex )
else
  ( cd "$BUILD" && "$JAVA_HOME/bin/jar$EXE" uf base.apk classes.dex )
fi
if command -v unzip >/dev/null 2>&1; then
  unzip -l "$BUILD/base.apk" | grep -q classes.dex || die "classes.dex missing from base.apk"
fi

log "[5/6] zipalign"
"$ZIPALIGN" -f 4 "$(to_native "$BUILD/base.apk")" "$(to_native "$BUILD/aligned.apk")"

log "[6/6] sign (v1 + v2)"
if [ ! -f debug.keystore ]; then
  log "       generating debug.keystore (gitignored, password xpan1234)"
  "$KEYTOOL" -genkeypair -keystore "$(to_native debug.keystore)" -storetype JKS \
    -alias xpan -storepass xpan1234 -keypass xpan1234 \
    -dname "CN=XPanOverlay" -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
fi

if [ -f "$APKSIGNER_JAR" ]; then
  # apksigner 25.x reaches into java.io.Console and sun.security.x509,
  # both of which JDK 9+ hides behind the module system
  SIGNER_JVM=()
  if [ "${JAVAC_MAJOR:-1}" -ge 9 ] 2>/dev/null; then
    SIGNER_JVM=(
      --add-opens java.base/java.io=ALL-UNNAMED
      --add-exports java.base/sun.security.x509=ALL-UNNAMED
      --add-exports java.base/sun.security.pkcs=ALL-UNNAMED
      --add-exports java.base/sun.security.util=ALL-UNNAMED
    )
  fi
  "$JAVA" "${SIGNER_JVM[@]}" -jar "$(to_native "$APKSIGNER_JAR")" sign \
    --ks "$(to_native debug.keystore)" --ks-pass pass:xpan1234 --key-pass pass:xpan1234 \
    --ks-key-alias xpan --min-sdk-version 10 \
    --v1-signing-enabled true --v2-signing-enabled true \
    --out "$(to_native "$BUILD/$OUT_APK")" "$(to_native "$BUILD/aligned.apk")"
else
  warn "apksigner.jar not found in $(basename "$BT_DIR")/lib - falling back to jarsigner (v1 only)"
  cp "$BUILD/aligned.apk" "$BUILD/$OUT_APK"
  "$JARSIGNER" -keystore "$(to_native debug.keystore)" -storepass xpan1234 \
    -sigalg SHA1withRSA -digestalg SHA1 \
    "$(to_native "$BUILD/$OUT_APK")" xpan >/dev/null
fi

SIZE=$(ls -lh "$BUILD/$OUT_APK" | awk '{print $5}')
log "DONE: $BUILD/$OUT_APK ($SIZE)"
log "install with pmca-gui / pmca-console"
