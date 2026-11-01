#!/usr/bin/env bash
set -u
S="$HOME/theos/sdks/iPhoneOS27.2.sdk"
echo "===== libSystem.tbd head ====="
head -12 "$S/usr/lib/libSystem.tbd"
echo "===== UIKit.tbd head ====="
head -8 "$S/System/Library/Frameworks/UIKit.framework/UIKit.tbd"
echo "===== count of tbd with arm64e.x1 ====="
grep -rl "arm64e.x1-ios" "$S" --include="*.tbd" 2>/dev/null | wc -l
echo "===== total tbd ====="
find "$S" -name "*.tbd" | wc -l
echo "===== any per-arch symbol tables? ====="
grep -rl "arm64e.x1-ios" "$S" --include="*.tbd" 2>/dev/null | head -3 | while read -r f; do
  echo "--- $f"
  grep -n -A3 "^symbols:" "$f" | head -12
done
