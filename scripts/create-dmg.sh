#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    printf 'Usage: %s app-path output-path\n' "$0" >&2
    exit 64
fi

app_path=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
output_directory=$(dirname "$2")
mkdir -p "$output_directory"
output_path=$(cd "$output_directory" && pwd)/$(basename "$2")
staging_directory=$(mktemp -d "${TMPDIR:-/tmp}/MondayChan-DMG.XXXXXX")
trap 'rm -rf "$staging_directory"' EXIT
repository_root=$(cd "$(dirname "$0")/.." && pwd)

if ! command -v appdmg >/dev/null 2>&1; then
    printf 'appdmg is required.\n' >&2
    exit 69
fi

ditto "$app_path" "$staging_directory/Monday-chan.app"
ditto "$repository_root/packaging/DMG/Background.png" "$staging_directory/Background.png"
ditto "$repository_root/packaging/DMG/Background@2x.png" "$staging_directory/Background@2x.png"
ditto "$app_path/Contents/Resources/AppIcon.icns" "$staging_directory/AppIcon.icns"
cat > "$staging_directory/appdmg.json" <<JSON
{
  "title": "Monday-chan",
  "icon": "AppIcon.icns",
  "background": "Background.png",
  "icon-size": 128,
  "window": {
    "position": { "x": 220, "y": 120 },
    "size": { "width": 660, "height": 422 }
  },
  "format": "UDZO",
  "filesystem": "HFS+",
  "contents": [
    { "x": 180, "y": 200, "type": "file", "path": "Monday-chan.app" },
    { "x": 480, "y": 200, "type": "link", "path": "/Applications" }
  ]
}
JSON

rm -f "$output_path"
appdmg "$staging_directory/appdmg.json" "$output_path"

if [ -n "${CODE_SIGN_IDENTITY:-}" ] && [ "$CODE_SIGN_IDENTITY" != "-" ]; then
    codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$output_path"
fi
printf '%s\n' "$output_path"
