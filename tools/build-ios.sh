#!/usr/bin/env bash
# 通用 iOS 未签名 ipa 构建脚本（arm64 + iOS 27 SDK，无 Xcode）
# 用法: build-ios.sh <src-dir> <AppName> <bundle-id> [min-ios] [frameworks...]
set -euo pipefail

SRC="${1:?src dir}"
APP_NAME="${2:?app name}"
BUNDLE_ID="${3:?bundle id}"
MIN_IOS="${4:-27.0}"
shift 4 || true
FRAMEWORKS=("$@")
if [ ${#FRAMEWORKS[@]} -eq 0 ]; then
  FRAMEWORKS=(UIKit Foundation CoreGraphics QuartzCore)
fi

SDK="${SDK:-$HOME/theos/sdks/iPhoneOS27.2-patched.sdk}"
SDK_VER="$(grep -o '"Version":"[0-9.]*"' "$SDK/SDKSettings.json" | head -1 | sed 's/.*:"//; s/"//')"
LD=/usr/bin/ld64.lld-18
OUT="${OUT_DIR:-$HOME/imdsh-out}"
BUILD="$OUT/build"
APP="$OUT/$APP_NAME.app"

rm -rf "$BUILD" "$APP"
mkdir -p "$BUILD" "$APP"

# 1) compile every .m under src
INCLUDES=()
while IFS= read -r d; do INCLUDES+=(-I"$d"); done < <(find "$SRC" -type d | sort)

OBJS=()
while IFS= read -r f; do
  o="$BUILD/$(echo "${f#"$SRC"/}" | tr '/' '_' | sed 's/\.m$/.o/')"
  clang -target arm64-apple-ios$MIN_IOS -isysroot "$SDK" -fobjc-arc -O2 \
    -fno-modules -DUSE_UIKIT_PUBLIC_HEADERS=1 \
    -F"$SDK/System/Library/Frameworks" -F"$SDK/System/Library/PrivateFrameworks" \
    -F"$SDK/System/Library/SubFrameworks" "${INCLUDES[@]}" -c "$f" -o "$o"
  OBJS+=("$o")
done < <(find "$SRC" -name '*.m' | sort)

echo "== compiled ${#OBJS[@]} objects =="

# 2) link
LDFLAGS=(-arch arm64 -platform_version ios "$MIN_IOS" "$SDK_VER" -syslibroot "$SDK" -L"$SDK/usr/lib" -lSystem -lobjc
  -F"$SDK/System/Library/Frameworks" -F"$SDK/System/Library/PrivateFrameworks" -F"$SDK/System/Library/SubFrameworks")
for fw in "${FRAMEWORKS[@]}"; do LDFLAGS+=(-framework "$fw"); done
"$LD" "${LDFLAGS[@]}" -o "$APP/$APP_NAME" "${OBJS[@]}"
echo "== linked: $(file -b "$APP/$APP_NAME") =="

# 3) resources + Info.plist
if [ -d "$SRC/Resources" ]; then cp -R "$SRC/Resources/." "$APP/" 2>/dev/null || true; fi
if [ -f "$SRC/Info.plist" ]; then
  cp "$SRC/Info.plist" "$APP/Info.plist"
else
  python3 - "$APP/Info.plist" "$APP_NAME" "$BUNDLE_ID" "$MIN_IOS" <<'PY'
import plistlib, sys
path, name, bundle, minios = sys.argv[1:5]
plist = {
    "CFBundleDevelopmentRegion": "zh_CN",
    "CFBundleDisplayName": "IMDSH",
    "CFBundleExecutable": name,
    "CFBundleIdentifier": bundle,
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": name,
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "1.0.0",
    "CFBundleVersion": "1",
    "MinimumOSVersion": minios,
    "CFBundleSupportedPlatforms": ["iPhoneOS"],
    "LSRequiresIPhoneOS": True,
    "UIDeviceFamily": [1, 2],
    "UILaunchScreen": {},
    "UIRequiredDeviceCapabilities": ["arm64"],
    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
}
with open(path, "wb") as fh:
    plistlib.dump(plist, fh)
PY
fi
printf 'APPL????' > "$APP/PkgInfo"
rm -rf "$APP/_CodeSignature"

# 4) package
rm -rf "$OUT/Payload" "$OUT/$APP_NAME-unsigned.ipa"
mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
( cd "$OUT" && zip -qry "$APP_NAME-unsigned.ipa" Payload )
rm -rf "$OUT/Payload"
echo "== ipa: $OUT/$APP_NAME-unsigned.ipa ($(du -h "$OUT/$APP_NAME-unsigned.ipa" | cut -f1)) =="
