#!/bin/sh
# Xcode Cloud post-clone: stamp CFBundleVersion from the CI run number.
#
# WHY THIS EXISTS — runs #40 and #41 (2026-08-27) both died AFTER
# "** ARCHIVE SUCCEEDED **" with no compile error and no artifacts on #41.
# The cause was a build-number collision, not code:
#
#   Xcode Cloud does NOT inject the build number. The value committed in
#   EVVMobile/Info.plist is what gets uploaded. Commit history proves it
#   (commit "build 28" -> TestFlight 28, "build 29" -> 29, ... "build 32" -> 32).
#
# On 2026-08-26 a burst of runs consumed TestFlight builds 33-39, but the repo
# plist was still sitting at 33. App Store Connect rejects any upload whose
# CFBundleVersion is not greater than every existing build for the version, so
# the archive built fine and then the upload was refused. Retriggering the same
# commit could never fix it — it re-uploaded the same colliding 33.
#
# CI_BUILD_NUMBER is the workflow run number, which only ever increases and is
# already ahead of the consumed numbers, so stamping it makes collisions
# structurally impossible instead of relying on a human remembering to bump.
#
# Local/dev builds never run this, so the committed plist value still matters
# as a sane fallback — keep bumping it, but CI is now authoritative.
set -eu

PLIST="$CI_PRIMARY_REPOSITORY_PATH/EVVMobile/Info.plist"

if [ -z "${CI_BUILD_NUMBER:-}" ]; then
  echo "ci_post_clone: CI_BUILD_NUMBER unset; leaving committed CFBundleVersion as-is."
  exit 0
fi

if [ ! -f "$PLIST" ]; then
  echo "ci_post_clone: ERROR: no Info.plist at $PLIST" >&2
  exit 1
fi

OLD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST" 2>/dev/null || echo "?")
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CI_BUILD_NUMBER" "$PLIST"
echo "ci_post_clone: CFBundleVersion $OLD -> $CI_BUILD_NUMBER (from CI run number)"
