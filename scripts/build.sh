#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
build_directory=$(swift build -c release --show-bin-path)
icon_directory="$build_directory/AppIcon"
scripts/compile-icon.sh "$icon_directory"
app_directory="$PWD/dist/MondayChan.app"
if [ -d "$app_directory" ]; then
    rm -r "$app_directory"
fi
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp "$build_directory/MondayChan" "$app_directory/Contents/MacOS/MondayChan"
for resource in "$build_directory"/MondayChan_*.bundle; do
    ditto "$resource" "$app_directory/Contents/Resources/$(basename "$resource")"
done
cp packaging/Info.plist "$app_directory/Contents/Info.plist"
for localization in packaging/*.lproj; do
    ditto "$localization" "$app_directory/Contents/Resources/$(basename "$localization")"
done
cp "$icon_directory/AppIcon.icns" "$icon_directory/Assets.car" "$app_directory/Contents/Resources/"
codesign --force --deep --sign - "$app_directory"
printf '%s\n' "$app_directory"
