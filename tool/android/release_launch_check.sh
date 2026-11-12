#!/usr/bin/env bash
# Release launch check (android-emulator.yml): installs a release APK on the
# running emulator, starts the app, waits, and fails when the process is gone.
# The crash buffer and the app's log lines go to the job log either way, so a
# crash on launch can be read without a device.
#
# Usage: release_launch_check.sh <apk> <package> [seconds]
set -u
apk=$1
package=$2
seconds=${3:-20}

if ! adb install -r -g "$apk"; then
  echo "::error::릴리스 APK를 설치하지 못했어요: $apk"
  exit 1
fi
adb logcat -c
adb shell am start -W -n "$package/.MainActivity"
sleep "$seconds"
pid=$(adb shell pidof "$package" | tr -d '\r')

echo "::group::logcat — crash buffer"
adb logcat -d -b crash
echo "::endgroup::"
echo "::group::logcat — AndroidRuntime, native crashes, flutter, $package"
adb logcat -d -v brief | grep -E "AndroidRuntime|FATAL|DEBUG|libc|flutter|$package" | tail -n 400
echo "::endgroup::"

adb uninstall "$package" > /dev/null
if [ -z "$pid" ]; then
  echo "::error::릴리스 APK가 시작한 뒤 ${seconds}초 안에 꺼졌어요 — 위 logcat을 보세요"
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "릴리스 실행: ${seconds}초 안에 꺼짐" >> "$GITHUB_STEP_SUMMARY"
  exit 1
fi
echo "release launch: still running after ${seconds} s (pid $pid)"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "릴리스 실행: ${seconds}초 뒤에도 실행 중" >> "$GITHUB_STEP_SUMMARY"
exit 0
