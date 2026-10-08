#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# build-android-flutter.sh — Manual Flutter Android build script
# Usage: ./build-android-flutter.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$SCRIPT_DIR/flutter"

echo "═══════════════════════════════════════════════════════"
echo "  Svitlo — Flutter Android build"
echo "═══════════════════════════════════════════════════════"

# ── 1. Check Flutter ─────────────────────────────────────────────────────────
if ! command -v flutter &>/dev/null; then
  echo ""
  echo "❌ flutter not found in PATH."
  echo "   Install Flutter SDK: https://docs.flutter.dev/get-started/install/linux"
  echo "   Then add the 'bin' directory to your PATH."
  exit 1
fi
echo "✅ Flutter: $(flutter --version | head -1)"

# ── 2. Detect Android SDK ────────────────────────────────────────────────────
ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"

if [[ -z "$ANDROID_SDK" ]]; then
  for candidate in \
    "$HOME/Android/Sdk" \
    "$HOME/.android/sdk" \
    "/opt/android-sdk" \
    "/usr/lib/android-sdk"; do
    if [[ -d "$candidate" ]]; then
      ANDROID_SDK="$candidate"
      break
    fi
  done
fi

if [[ -z "$ANDROID_SDK" ]] || [[ ! -d "$ANDROID_SDK" ]]; then
  echo ""
  echo "❌ Android SDK not found."
  echo "   Install Android Studio or standalone Android command-line tools."
  echo "   Then set ANDROID_HOME=/path/to/sdk before running this script."
  exit 1
fi
echo "✅ Android SDK: $ANDROID_SDK"

# ── 3. Detect Flutter SDK path (needed for local.properties) ─────────────────
FLUTTER_BIN="$(command -v flutter)"
# flutter symlink → real path → two levels up = SDK root
FLUTTER_SDK="$(cd "$(dirname "$(readlink -f "$FLUTTER_BIN")")" && cd .. && pwd)"
echo "✅ Flutter SDK root: $FLUTTER_SDK"

# ── 4. Write local.properties ────────────────────────────────────────────────
cat > "$FLUTTER_DIR/android/local.properties" <<EOF
sdk.dir=$ANDROID_SDK
flutter.sdk=$FLUTTER_SDK
flutter.buildMode=release
flutter.versionName=1.0.0
flutter.versionCode=1
EOF
echo "✅ android/local.properties written"

# ── 5. flutter pub get ───────────────────────────────────────────────────────
echo ""
echo "📦 Installing Dart packages..."
cd "$FLUTTER_DIR"
flutter pub get

# ── 6. Build release APK ─────────────────────────────────────────────────────
echo ""
echo "🔨 Building release APKs split by ABI (arm64-v8a + armeabi-v7a)..."
# Gradle can eat all RAM and freeze the PC. Run the build in a cgroup with a
# hard memory cap (override with BUILD_MEM_MAX=4G): if exceeded, only the build
# is killed. Also stop leftover daemons and don't keep a new one alive after.
BUILD_MEM_MAX="${BUILD_MEM_MAX:-3G}"
(cd android && ./gradlew --stop >/dev/null 2>&1 || true)
export GRADLE_OPTS="-Dorg.gradle.daemon=false"
BUILD_CMD=(flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64)
if command -v systemd-run &>/dev/null && systemd-run --user --scope -q true 2>/dev/null; then
  echo "   (memory limit: $BUILD_MEM_MAX, low CPU/IO priority)"
  systemd-run --user --scope -q \
    -p MemoryMax="$BUILD_MEM_MAX" -p MemorySwapMax=0 -p CPUWeight=20 -p IOWeight=20 \
    nice -n 10 "${BUILD_CMD[@]}"
else
  echo "   ⚠️  systemd-run unavailable — building without memory limit"
  nice -n 10 "${BUILD_CMD[@]}"
fi

# ── 7. Copy APK to repo root ─────────────────────────────────────────────────
# Prefer arm64-v8a (all modern phones); fall back to armeabi-v7a.
APK_OUT="$FLUTTER_DIR/build/app/outputs/flutter-apk"
APK_SRC=""
for abi in arm64-v8a armeabi-v7a; do
  candidate="$APK_OUT/app-${abi}-release.apk"
  if [[ -f "$candidate" ]]; then
    APK_SRC="$candidate"
    SELECTED_ABI="$abi"
    break
  fi
done

APK_DST="$SCRIPT_DIR/svitlo-flutter.apk"

if [[ -n "$APK_SRC" ]]; then
  cp "$APK_SRC" "$APK_DST"
  SIZE=$(du -sh "$APK_DST" | cut -f1)
  echo ""
  echo "  📦 All split APKs:"
  for f in "$APK_OUT"/app-*-release.apk; do
    echo "     $(du -sh "$f" | cut -f1)  $(basename "$f")"
  done
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  ✅ Build successful!"
  echo "  ABI    : $SELECTED_ABI (copied as svitlo-flutter.apk)"
  echo "  Output : $APK_DST"
  echo "  Size   : $SIZE"
  echo "═══════════════════════════════════════════════════════"
else
  echo ""
  echo "❌ APK not found in: $APK_OUT"
  echo "   Check build output above for errors."
  exit 1
fi
