#!/usr/bin/env bash
# 快速语法检查（不链接）：check-ios.sh [文件或目录...]，默认检查 imdsh/ios/src 全量。
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../ios" && pwd)"
SDK="${SDK:-$HOME/theos/sdks/iPhoneOS27.2-patched.sdk}"
TARGET="${TARGET:-arm64-apple-ios27.0}"

INCLUDES=()
while IFS= read -r d; do INCLUDES+=(-I"$d"); done < <(find "$ROOT/src" -type d | sort)

FLAGS=(-target "$TARGET" -isysroot "$SDK" -fobjc-arc -fsyntax-only -fno-modules
  -DUSE_UIKIT_PUBLIC_HEADERS=1 -Wall -Wno-unused-parameter
  -F"$SDK/System/Library/Frameworks" -F"$SDK/System/Library/PrivateFrameworks"
  -F"$SDK/System/Library/SubFrameworks" "${INCLUDES[@]}")

FILES=()
if [ $# -eq 0 ]; then
  while IFS= read -r f; do FILES+=("$f"); done < <(find "$ROOT/src" -name '*.m' | sort)
else
  for arg in "$@"; do
    if [ -d "$arg" ]; then
      while IFS= read -r f; do FILES+=("$f"); done < <(find "$arg" -name '*.m' | sort)
    else
      FILES+=("$arg")
    fi
  done
fi

fail=0
for f in "${FILES[@]}"; do
  err=$(clang "${FLAGS[@]}" "$f" 2>&1)
  if [ -n "$err" ]; then
    echo "### $f"
    echo "$err" | head -40
    fail=$((fail+1))
  fi
done
echo "---- checked ${#FILES[@]} files, ${fail} with diagnostics ----"
