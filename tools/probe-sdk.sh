#!/usr/bin/env bash
set -u
S="$HOME/theos/sdks/iPhoneOS27.2.sdk"
echo "== sdk dir =="
du -sh "$S"
echo "== UIKit headers with Glass =="
grep -rln "UIGlass" "$S/System/Library/Frameworks/UIKit.framework/Headers/" 2>/dev/null | head -20
echo "== glass symbols in tbd =="
grep -o "_OBJC_CLASS_\$_UIGlass[A-Za-z]*" "$S/System/Library/Frameworks/UIKit.framework/UIKit.tbd" 2>/dev/null | sort -u | head -20
grep -o "_UIGlass[A-Za-z]*" "$S/System/Library/Frameworks/UIKit.framework/UIKit.tbd" 2>/dev/null | sort -u | head -30
echo "== SDK version =="
grep -o '"Version"[^,]*' "$S/SDKSettings.json" | head -3
grep -o 'MinimumSDKVersion[^,]*' "$S/SDKSettings.json" | head -3
echo "== frameworks count =="
ls "$S/System/Library/Frameworks/" | wc -l
echo "== tint/glass pod headers =="
ls "$S/System/Library/Frameworks/UIKit.framework/Headers/" | grep -i glass
