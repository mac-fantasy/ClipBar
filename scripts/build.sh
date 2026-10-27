#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration=release
arch_args=()

for option in "$@"; do
    case "$option" in
        --debug) configuration=debug ;;
        --universal) arch_args=(--arch arm64 --arch x86_64) ;;
        *) printf '未知参数：%s\n用法：./scripts/build.sh [--debug] [--universal]\n' "$option" >&2; exit 1 ;;
    esac
done

cd "$project_dir"
swift build -c "$configuration" ${arch_args[@]+"${arch_args[@]}"}
binary_dir="$(swift build -c "$configuration" ${arch_args[@]+"${arch_args[@]}"} --show-bin-path)"
output_dir="$project_dir/dist"
staging_dir="$output_dir/.ClipBar-staging-$$"
app_dir="$staging_dir/ClipBar.app"
iconset_dir="$staging_dir/AppIcon.iconset"

trap 'rm -rf "$staging_dir"' EXIT
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$iconset_dir"
cp "$binary_dir/ClipBar" "$app_dir/Contents/MacOS/ClipBar"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
python3 scripts/configure-bundle.py "$app_dir/Contents/Info.plist"
# SwiftPM links the binary framework but does not embed it in a hand-built .app.
sparkle_framework="$project_dir/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ ! -d "$sparkle_framework" ]; then
    printf '找不到 SwiftPM 下载的 Sparkle.framework：%s\n' "$sparkle_framework" >&2
    exit 1
fi
mkdir -p "$app_dir/Contents/Frameworks"
ditto "$sparkle_framework" "$app_dir/Contents/Frameworks/Sparkle.framework"
swift scripts/generate-icon.swift "$iconset_dir"
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/AppIcon.icns"
plutil -lint "$app_dir/Contents/Info.plist"
# Preserve Sparkle's vendor signatures on nested helpers and XPC services.
codesign --force --sign - --timestamp=none "$app_dir"
codesign --verify --deep --strict "$app_dir"

if [ -d "$output_dir/ClipBar.app" ]; then
    rm -rf "$output_dir/ClipBar.app"
fi
mv "$app_dir" "$output_dir/ClipBar.app"
printf '\n构建完成：%s/ClipBar.app\n运行：open "%s/ClipBar.app"\n' "$output_dir" "$output_dir"
