#!/bin/zsh
# Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
destination="${1:-$project_dir/dist}"
build_mode="${2:-universal}"
layout="${3:-finder}"
case "$build_mode" in
    native) package_label="$(uname -m)"; minimum_gib=3 ;;
    universal) package_label="Universal"; minimum_gib=4 ;;
    *) print -u2 "Usage: $0 [OUTPUT_DIRECTORY] [native|universal] [plain|finder]"; exit 2 ;;
esac
case "$layout" in plain|finder) ;; *) print -u2 "Layout must be plain or finder"; exit 2 ;; esac
app_name="Codex Aura"
app_path="$destination/$app_name.app"
guide_name="Codex Aura 安装说明.txt"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/AppBundle/Info.plist")"
volume_name="$app_name"
dmg_path="$destination/$app_name $version $package_label.dmg"
zip_path="$destination/$app_name $version $package_label.dmg.zip"
available_kib="$(df -Pk "$project_dir" | awk 'NR==2 {print $4}')"
if (( available_kib < minimum_gib * 1024 * 1024 )); then
    print -u2 "At least $minimum_gib GiB free is required for this release build. No output was changed."
    exit 1
fi
work_dir="$(mktemp -d /private/tmp/codexaura-release.XXXXXX)"
attached_device=""

cleanup() {
    if [[ -n "${attached_device:-}" ]]; then
        hdiutil detach "$attached_device" -quiet 2>/dev/null || true
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT

render_svg() {
    mkdir -p "$work_dir/render-cache"
    CLANG_MODULE_CACHE_PATH="$work_dir/render-cache" \
        swift "$project_dir/scripts/render_svg.swift" "$@"
}

build_arch() {
    local arch="$1"
    local triple="$arch-apple-macosx14.0"
    local scratch="$project_dir/.build-$arch"
    local cache="$project_dir/.cache/$arch"

    mkdir -p "$cache/clang" "$cache/swiftpm"
    CLANG_MODULE_CACHE_PATH="$cache/clang" \
    SWIFTPM_MODULECACHE_OVERRIDE="$cache/swiftpm" \
    swift build \
        --package-path "$project_dir" \
        --scratch-path "$scratch" \
        --triple "$triple" \
        --jobs 2 \
        -Xswiftc -debug-prefix-map -Xswiftc "$project_dir=." \
        -Xswiftc -file-prefix-map -Xswiftc "$project_dir=." \
        -Xcc "-ffile-prefix-map=$project_dir=." \
        -c release
}

make_icon() {
    local source="$project_dir/AppBundle/AppIcon.svg"
    local iconset="$work_dir/AppIcon.iconset"
    local master="$work_dir/AppIcon-1024.png"
    mkdir -p "$iconset"
    render_svg "$source" "$master" 1024 1024

    sips -z 16 16 "$master" --out "$iconset/icon_16x16.png" >/dev/null
    sips -z 32 32 "$master" --out "$iconset/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$master" --out "$iconset/icon_32x32.png" >/dev/null
    sips -z 64 64 "$master" --out "$iconset/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$master" --out "$iconset/icon_128x128.png" >/dev/null
    sips -z 256 256 "$master" --out "$iconset/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$master" --out "$iconset/icon_256x256.png" >/dev/null
    sips -z 512 512 "$master" --out "$iconset/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$master" --out "$iconset/icon_512x512.png" >/dev/null
    cp "$master" "$iconset/icon_512x512@2x.png"
    iconutil -c icns "$iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
}

cd "$project_dir"
mkdir -p "$destination"

if [[ "$build_mode" == "native" ]]; then
    echo "[1/6] Building native $package_label…"
    build_arch "$package_label"
else
    echo "[1/6] Building arm64…"
    build_arch arm64
    echo "[2/6] Building x86_64…"
    build_arch x86_64
fi

echo "[3/6] Creating app…"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
if [[ "$build_mode" == "native" ]]; then
    cp "$project_dir/.build-$package_label/$package_label-apple-macosx/release/CodexAura" "$app_path/Contents/MacOS/CodexAura"
else
    lipo -create \
        "$project_dir/.build-arm64/arm64-apple-macosx/release/CodexAura" \
        "$project_dir/.build-x86_64/x86_64-apple-macosx/release/CodexAura" \
        -output "$app_path/Contents/MacOS/CodexAura"
fi
cp "$project_dir/AppBundle/Info.plist" "$app_path/Contents/Info.plist"
chmod +x "$app_path/Contents/MacOS/CodexAura"
make_icon
cp "$project_dir/LICENSE" "$project_dir/NOTICE" "$project_dir/THIRD_PARTY_NOTICES.md" "$app_path/Contents/Resources/"
strip -S "$app_path/Contents/MacOS/CodexAura"
python3 "$project_dir/scripts/check_release_paths.py" "$app_path"
codesign --force --sign - "$app_path"

echo "[4/6] Preparing installer…"
staging="$work_dir/staging"
mkdir -p "$staging/.background"
ditto "$app_path" "$staging/$app_name.app"
ln -s /Applications "$staging/Applications"
cp "$project_dir/AppBundle/$guide_name" "$staging/$guide_name"
cp "$project_dir/AppBundle/$guide_name" "$destination/$guide_name"
render_svg \
    "$project_dir/AppBundle/DMGBackground.svg" \
    "$staging/.background/background.png" 700 440


if [[ "$layout" == "plain" ]]; then
    echo "[5/6] Creating plain DMG without Finder automation…"
    hdiutil create -quiet -volname "$volume_name" -srcfolder "$staging" \
        -ov -format UDZO -imagekey zlib-level=9 "$dmg_path"
else
    rw_dmg="$work_dir/$app_name-rw.dmg"
    hdiutil create -quiet -volname "$volume_name" -srcfolder "$staging" \
        -ov -format UDRW "$rw_dmg"

    echo "[5/6] Styling DMG…"
    attach_output="$(hdiutil attach -readwrite -noverify -noautoopen "$rw_dmg")"
    attached_device="$(print -r -- "$attach_output" | awk '/\/Volumes\// { print $1; exit }')"
    mount_path="$(print -r -- "$attach_output" | awk '/\/Volumes\// { sub(/^.*\/Volumes\//, "/Volumes/"); print; exit }')"
    if [[ -z "$attached_device" || -z "$mount_path" ]]; then
        print -u2 "Unable to identify the mounted DMG device."
        exit 1
    fi
    mounted_volume_name="$(basename "$mount_path")"
    osascript <<APPLESCRIPT
    tell application "Finder"
        tell disk "$mounted_volume_name"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set pathbar visible of container window to false
            set bounds of container window to {120, 120, 820, 560}
            set theViewOptions to the icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 86
            set text size of theViewOptions to 12
            set background picture of theViewOptions to file ".background:background.png"
            set position of item "$app_name.app" of container window to {180, 210}
            set position of item "Applications" of container window to {520, 210}
            set position of item "$guide_name" of container window to {350, 348}
            update without registering applications
            delay 2
            close
        end tell
    end tell
APPLESCRIPT
    hdiutil detach "$attached_device" -quiet
    attached_device=""

    hdiutil convert -quiet "$rw_dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$dmg_path"
fi

echo "[6/6] Compressing and verifying…"
rm -f "$zip_path"
python3 - "$dmg_path" "$zip_path" <<'PYZIP'
from pathlib import Path
import sys, zipfile
source = Path(sys.argv[1])
with zipfile.ZipFile(sys.argv[2], 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    archive.write(source, arcname=source.name)
PYZIP
unzip -t "$zip_path" >/dev/null
hdiutil verify "$dmg_path" >/dev/null
codesign --verify --deep --strict "$app_path"
lipo -info "$app_path/Contents/MacOS/CodexAura"

(cd "$destination" && shasum -a 256 "$app_name $version $package_label.dmg" "$app_name $version $package_label.dmg.zip" > "SHA256SUMS-$version.txt")
echo "Signing: ad-hoc, not notarized"
echo "App: $app_path"
echo "DMG: $dmg_path"
echo "ZIP: $zip_path"
