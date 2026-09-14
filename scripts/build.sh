#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration=${BUILD_CONFIGURATION:-release}
architectures=${MONDAY_ARCHITECTURES:-"arm64 x86_64"}
app_directory=${MONDAY_APP_PATH:-"$PWD/dist/MondayChan.app"}
version=${APP_VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" packaging/Info.plist)}
build_number=${APP_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" packaging/Info.plist)}
binaries=()
resource_directory=
read -r -a architecture_list <<< "$architectures"

for architecture in "${architecture_list[@]}"; do
    case "$architecture" in
        arm64|x86_64) ;;
        *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 64 ;;
    esac
    scratch_directory="$PWD/.build/package-$architecture"
    build_arguments=(-c "$configuration" --triple "$architecture-apple-macosx14.0" --scratch-path "$scratch_directory" --product MondayChan)
    swift build "${build_arguments[@]}"
    build_directory=$(swift build "${build_arguments[@]}" --show-bin-path)
    binaries+=("$build_directory/MondayChan")
    if [ -z "$resource_directory" ]; then
        resource_directory=$build_directory
    fi
done

icon_directory="$PWD/.build/AppIcon"
scripts/compile-icon.sh "$icon_directory"
rm -rf "$app_directory"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"

if [ "${#binaries[@]}" -eq 1 ]; then
    cp "${binaries[0]}" "$app_directory/Contents/MacOS/MondayChan"
else
    lipo -create "${binaries[@]}" -output "$app_directory/Contents/MacOS/MondayChan"
    index=0
    for architecture in "${architecture_list[@]}"; do
        extracted="$PWD/.build/MondayChan-$architecture"
        lipo -thin "$architecture" "$app_directory/Contents/MacOS/MondayChan" -output "$extracted"
        cmp "$extracted" "${binaries[$index]}"
        rm "$extracted"
        index=$((index + 1))
    done
fi

shopt -s nullglob
for resource in "$resource_directory"/MondayChan_*.bundle; do
    ditto "$resource" "$app_directory/Contents/Resources/$(basename "$resource")"
done
cp packaging/Info.plist "$app_directory/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app_directory/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app_directory/Contents/Info.plist"
for localization in packaging/*.lproj; do
    ditto "$localization" "$app_directory/Contents/Resources/$(basename "$localization")"
done
cp "$icon_directory/AppIcon.icns" "$icon_directory/Assets.car" "$app_directory/Contents/Resources/"

signing_identity=${CODE_SIGN_IDENTITY:--}
signing_arguments=(--force --sign "$signing_identity")
if [ "$signing_identity" != "-" ]; then
    signing_arguments+=(--options runtime --timestamp)
fi
if [ -n "${CODE_SIGN_ENTITLEMENTS:-}" ]; then
    signing_arguments+=(--entitlements "$CODE_SIGN_ENTITLEMENTS")
fi
codesign "${signing_arguments[@]}" "$app_directory"
printf '%s\n' "$app_directory"
