#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

# Keep compiler caches inside the project so builds work in restricted environments.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
# Sign with the stable self-signed "MacSnip Release" certificate, shared with the other apps, when it
# is in the keychain. Every release then has the same signer, so an installed copy can be checked
# against it. Set SIGN_IDENTITY to use another certificate, or "-" to force ad-hoc signing.
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  if security find-certificate -c "MacSnip Release" >/dev/null 2>&1; then
    identity="MacSnip Release"
  else
    identity="-"
  fi
fi
architectures=()
if [[ "${1:-}" == "--universal" ]]; then
  architectures=(--arch arm64 --arch x86_64)
fi
swift build -c release --disable-sandbox -debug-info-format none "${architectures[@]}"
bin_path=$(swift build -c release --disable-sandbox -debug-info-format none "${architectures[@]}" --show-bin-path)
app="$PWD/dist.noindex/MacMural.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# Replace the executable instead of overwriting a binary that may be running.
cp "$bin_path/MacMural" "$app/Contents/MacOS/MacMural.new"
mv -f "$app/Contents/MacOS/MacMural.new" "$app/Contents/MacOS/MacMural"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$PWD/dist.noindex"
cp "$PWD/dist.noindex/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
# The hardened runtime enables library validation and ignores DYLD_* variables, so another process
# cannot inject code into the app. It works with any signature.
codesign --force --options runtime --sign "$identity" --identifier io.macmural.app "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$PWD/dist.noindex/MacMural.zip"
echo "Built: $app"
echo "Install: drag MacMural.app to Applications, then open it."
