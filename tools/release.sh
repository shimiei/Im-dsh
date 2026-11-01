#!/usr/bin/env bash
# 打包 IMDSH 未签名 ipa 到 Windows 侧 imdsh/dist/，并做产物自检。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
mkdir -p "$DIST"

echo "== build =="
OUT_DIR="$DIST" bash "$ROOT/tools/build-ios.sh" "$ROOT/ios/src" IMDSH com.imdsh.app 27.0 \
  UIKit Foundation CoreGraphics QuartzCore Security ImageIO UniformTypeIdentifiers QuickLook PhotosUI

IPA="$DIST/IMDSH-unsigned.ipa"
BIN="$DIST/IMDSH.app/IMDSH"

echo "== verify =="
file "$BIN"
xxd -l 4 "$BIN"
unzip -l "$IPA" | head -20
echo "== Info.plist =="
python3 - "$DIST/IMDSH.app/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as fh:
    p = plistlib.load(fh)
for key in ("CFBundleIdentifier", "CFBundleExecutable", "CFBundleShortVersionString",
            "MinimumOSVersion", "UIDeviceFamily"):
    print(f"  {key} = {p.get(key)}")
PY
echo "== size =="
du -h "$IPA"
echo "== done: $IPA =="
