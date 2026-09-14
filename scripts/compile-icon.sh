#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ]; then
    printf 'Usage: %s output-directory\n' "$0" >&2
    exit 64
fi

mkdir -p "$1"
xcrun actool packaging/AppIcon.icon \
    --compile "$1" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --target-device mac \
    --app-icon AppIcon \
    --standalone-icon-behavior all \
    --output-partial-info-plist "$1/partial.plist" \
    --output-format human-readable-text \
    --warnings --notices
