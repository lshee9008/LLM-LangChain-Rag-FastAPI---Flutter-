#!/bin/sh
set -eu

# Flutter assemble splits -d values on commas. Keep these paths relative to the
# Flutter project so this workspace's comma-containing name is parsed intact.
if [ -n "${FLUTTER_TARGET:-}" ] && [ -n "${FLUTTER_APPLICATION_PATH:-}" ]; then
  case "$FLUTTER_TARGET" in
    "$FLUTTER_APPLICATION_PATH"/*)
      FLUTTER_TARGET=${FLUTTER_TARGET#"$FLUTTER_APPLICATION_PATH"/}
      export FLUTTER_TARGET
      ;;
  esac
fi

SRCROOT=ios
export SRCROOT
exec /bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" "$@"
