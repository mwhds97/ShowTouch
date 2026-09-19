#!/usr/bin/env bash
set -euo pipefail
: "${THEOS:?Set THEOS to your configured Theos directory}"
showtouch_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$showtouch_root"
# All components are Objective-C; no Swift compiler or bootstrap is used.
make FINALPACKAGE=1 "$@" package
