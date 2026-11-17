#!/usr/bin/env bash
# Ariuno real-device verification helper.
#
# Prerequisites:
#   1. iPhone unlocked and awake, trust this Mac.
#   2. Release archive exists at build/Ariuno.xcarchive (see docs/acceptance-report.md §8).
#   3. A cloud-game account available to the tester. This script never handles credentials.
#
# Usage:
#   scripts/device-verification.sh <UDID> [install|ui-tests|launch-trace|load-trace|all]
set -euo pipefail

UDID="${1:?usage: $0 <UDID> [install|ui-tests|launch-trace|load-trace|all]}"
ACTION="${2:-all}"
BUNDLE_ID="com.misswell.Ariuno"
APP="build/Ariuno.xcarchive/Products/Applications/Ariuno.app"

require_unlocked() {
  if ! xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1; then
    echo "Device is locked or app cannot launch. Unlock the iPhone and keep it awake." >&2
    exit 2
  fi
}

install_app() {
  xcrun devicectl device install app --device "$UDID" "$APP"
}

launch_trace() {
  require_unlocked
  mkdir -p build/evidence
  xcrun xctrace record \
    --device "$UDID" \
    --template 'App Launch' \
    --launch "$BUNDLE_ID" \
    --time-limit 45s \
    --output build/evidence/ariuno-launch.trace
  echo "Launch trace: build/evidence/ariuno-launch.trace"
}

load_trace() {
  require_unlocked
  mkdir -p build/evidence
  # Cold-start page load using the bundled Debug-only local page requires the Debug build.
  xcrun xctrace record \
    --device "$UDID" \
    --template 'Time Profiler' \
    --launch "$BUNDLE_ID" \
    --time-limit 60s \
    --output build/evidence/ariuno-time-profile.trace
  echo "Time Profiler trace: build/evidence/ariuno-time-profile.trace"
}

ui_tests() {
  require_unlocked
  xcodebuild -project Ariuno.xcodeproj -scheme AriunoUITests \
    -destination "platform=iOS,id=$UDID" \
    -derivedDataPath build/DeviceDerivedData \
    DEVELOPMENT_TEAM=U8U443D7ZL -allowProvisioningUpdates test
}

case "$ACTION" in
  install) install_app ;;
  launch-trace) launch_trace ;;
  load-trace) load_trace ;;
  ui-tests) ui_tests ;;
  all) install_app; ui_tests; launch_trace ;;
  *) echo "unknown action: $ACTION" >&2; exit 1 ;;
esac
