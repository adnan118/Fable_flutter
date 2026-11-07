#!/usr/bin/env bash
set -euo pipefail

# The emulator runner executes 'script' using /usr/bin/sh, so explicitly
# invoke this Bash file instead of relying on sh supporting pipefail.
adb wait-for-device
sdk="$(adb shell getprop ro.build.version.sdk | tr -d '\r')"
if ! [[ "$sdk" =~ ^[0-9]+$ ]] || (( sdk < 35 )); then
  echo "RC123 requires Android API 35 or above; found: $sdk" >&2
  exit 1
fi
echo "RC123 Android emulator API=$sdk"
flutter devices
# Real ExoPlayer Player.STATE_READY and STATE_ENDED are mandatory inside
# this integration test. Never treat an APK build or native ACK as success.
flutter test integration_test/rc122_protected_video_test.dart \
  -d emulator-5554 --reporter=expanded
