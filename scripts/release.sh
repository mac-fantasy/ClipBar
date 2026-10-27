#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
: "${CLIPBAR_VERSION:?需要 CLIPBAR_VERSION，例如 1.2.3}"
: "${CLIPBAR_UPDATE_REPOSITORY:?需要 CLIPBAR_UPDATE_REPOSITORY，例如 owner/ClipBar}"
: "${SPARKLE_PUBLIC_ED_KEY:?需要 SPARKLE_PUBLIC_ED_KEY}"
: "${SPARKLE_PRIVATE_ED_KEY:?需要 SPARKLE_PRIVATE_ED_KEY}"
release_tag="${RELEASE_TAG:-v$CLIPBAR_VERSION}"
if [ "$release_tag" != "v$CLIPBAR_VERSION" ]; then
    printf 'Tag 必须与版本号一致：v%s\n' "$CLIPBAR_VERSION" >&2
    exit 1
fi

./scripts/build.sh --universal
release_dir="$project_dir/dist/release"
if [ -e "$release_dir" ]; then
    # Keep previous output recoverable when retrying a local release build.
    mv "$release_dir" "$project_dir/dist/release-previous-$(date +%s)-$$"
fi
mkdir -p "$release_dir"
archive_name="ClipBar-${CLIPBAR_VERSION}-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent dist/ClipBar.app "$release_dir/$archive_name"

sparkle_bin="$project_dir/.build/artifacts/sparkle/Sparkle/bin"
printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$sparkle_bin/generate_appcast" \
    --ed-key-file - \
    --download-url-prefix "https://github.com/${CLIPBAR_UPDATE_REPOSITORY}/releases/download/${release_tag}/" \
    --maximum-versions 1 --maximum-deltas 0 \
    -o "$release_dir/appcast.xml" "$release_dir"

# generate_appcast may only warn when the public and private keys do not match.
# Never publish a feed that clients will be unable to verify.
signature="$(python3 scripts/validate-appcast.py "$release_dir/appcast.xml" "$release_dir/$archive_name")"
printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$sparkle_bin/sign_update" \
    --ed-key-file - --verify "$release_dir/$archive_name" "$signature"
printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$sparkle_bin/sign_update" \
    --ed-key-file - --verify "$release_dir/appcast.xml"
(
    cd "$release_dir"
    shasum -a 256 "$archive_name" appcast.xml > SHA256SUMS
)
printf '\n发布文件已就绪：%s\n' "$release_dir"
