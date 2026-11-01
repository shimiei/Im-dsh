#!/usr/bin/env bash
set -u
S="$HOME/theos/sdks/iPhoneOS27.2.sdk"
echo "===== UIGlassEffect.h ====="
cat "$S/System/Library/Frameworks/UIKit.framework/Headers/UIGlassEffect.h"
echo "===== tbd glass symbols ====="
grep -o 'UIGlass[A-Za-z]*' "$S/System/Library/Frameworks/UIKit.framework/UIKit.tbd" | sort -u
echo "===== UIVisualEffect glass mentions ====="
grep -n -i "glass" "$S/System/Library/Frameworks/UIKit.framework/Headers/UIVisualEffect.h" 2>/dev/null
echo "===== UIView glass API ====="
grep -rn -i "glassEffect\|UIGlassContainer" "$S/System/Library/Frameworks/UIKit.framework/Headers/" 2>/dev/null | grep -v "^.*UIGlassEffect.h" | head -40
