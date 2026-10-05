#!/bin/zsh
# Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
destination="${1:-$project_dir/dist}"
app_path="$destination/Codex Aura.app"
scratch="$project_dir/.build-native"
available_kib="$(df -Pk "$project_dir" | awk 'NR==2 {print $4}')"
if (( available_kib < 3 * 1024 * 1024 )); then
    print -u2 "At least 3 GiB free is required for a native release build. No output was changed."
    exit 1
fi

cd "$project_dir"
swift build -c release --jobs 2 --scratch-path "$scratch" \
    -Xswiftc -debug-prefix-map -Xswiftc "$project_dir=." \
    -Xswiftc -file-prefix-map -Xswiftc "$project_dir=." \
    -Xcc "-ffile-prefix-map=$project_dir=."
bin_path="$(swift build -c release --scratch-path "$scratch" --show-bin-path)"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/CodexAura" "$app_path/Contents/MacOS/CodexAura"
cp "$project_dir/AppBundle/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_dir/LICENSE" "$project_dir/NOTICE" "$project_dir/THIRD_PARTY_NOTICES.md" "$app_path/Contents/Resources/"
chmod +x "$app_path/Contents/MacOS/CodexAura"
strip -S "$app_path/Contents/MacOS/CodexAura"

work_dir="$(mktemp -d /private/tmp/codexaura-icon.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
iconset="$work_dir/AppIcon.iconset"
mkdir -p "$iconset"
swift "$project_dir/scripts/render_svg.swift" "$project_dir/AppBundle/AppIcon.svg" "$work_dir/icon.png" 1024 1024
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$work_dir/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -z "$doubled" "$doubled" "$work_dir/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
python3 "$project_dir/scripts/check_release_paths.py" "$app_path"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
print "$app_path"
