#!/usr/bin/env bash
set -u
S="$HOME/theos/sdks/iPhoneOS27.2-patched.sdk"
echo "== private frameworks sample =="
ls "$S/System/Library/PrivateFrameworks" | head -30
echo "== UIKitCore =="
ls -d "$S/System/Library/PrivateFrameworks/UIKitCore.framework" 2>/dev/null && ls "$S/System/Library/PrivateFrameworks/UIKitCore.framework" | head
echo "== UIUtilities =="
ls -d "$S/System/Library/PrivateFrameworks/UIUtilities.framework" 2>/dev/null && ls "$S/System/Library/PrivateFrameworks/UIUtilities.framework/Headers" 2>/dev/null | head
echo "== UIKitDefines.h =="
sed -n '1,20p' "$S/System/Library/Frameworks/UIKit.framework/Headers/UIKitDefines.h"
echo "== UIKit.h first 30 =="
sed -n '1,30p' "$S/System/Library/Frameworks/UIKit.framework/Headers/UIKit.h"
