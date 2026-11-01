#!/usr/bin/env bash
set -u
S="$HOME/theos/sdks/iPhoneOS27.2-patched.sdk"
O="$HOME/theos/sdks/iPhoneOS16.5.sdk"
echo "== find UIDefines.h =="
find "$S" -name "UIDefines.h" 2>/dev/null | head
echo "== find UIUtilities dirs =="
find "$S" -maxdepth 6 -name "UIUtilities*" 2>/dev/null | head
echo "== 16.5 counterpart =="
ls "$O/System/Library/Frameworks/UIKit.framework/Headers/UIKitDefines.h" 2>/dev/null && sed -n '1,14p' "$O/System/Library/Frameworks/UIKit.framework/Headers/UIKitDefines.h"
echo "== macros used from UIDefines in 27.2 headers =="
grep -rho "UIKIT_EXTERN\|UIKIT_STATIC_INLINE\|UIKIT_EXTERN_C\|UIKIT_CLASS_AVAILABLE" "$S/System/Library/Frameworks/UIKit.framework/Headers/UIKitDefines.h" | sort | uniq -c | head
