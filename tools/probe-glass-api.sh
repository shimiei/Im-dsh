#!/usr/bin/env bash
set -u
S="$HOME/theos/sdks/iPhoneOS27.2-patched.sdk/System/Library/Frameworks/UIKit.framework/Headers"
echo "=== UIVisualEffectView.h ==="
cat "$S/UIVisualEffectView.h"
echo "=== UICorner* headers ==="
ls "$S" | grep -i corner
echo "=== UICornerConfiguration.h ==="
cat "$S/UICornerConfiguration.h" 2>/dev/null | head -60
echo "=== UIButton glass refs ==="
grep -rn -i "glass" "$S/UIButtonConfiguration.h" "$S/UIBackgroundConfiguration.h" "$S/UIButton.h" 2>/dev/null | head -20
echo "=== UIBarAppearance / tabbar glass ==="
grep -rn -i "glass" "$S/UITabBarController.h" "$S/UINavigationBar.h" "$S/UIToolbar.h" 2>/dev/null | head -20
