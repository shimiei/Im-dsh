#!/usr/bin/env bash
# 生成一份 lld-18 可读的 SDK 副本：剔除 tbd 里 LLVM 18 不认识的 arm64e.x1-ios 目标。
# 原始 SDK 不做任何修改（硬链接 + 先 rm 再写，rename 不触碰原 inode）。
set -euo pipefail
SRC="$HOME/theos/sdks/iPhoneOS27.2.sdk"
DST="$HOME/theos/sdks/iPhoneOS27.2-patched.sdk"

if [ -d "$DST" ]; then
  echo "== already patched: $DST =="
  exit 0
fi

echo "== hardlink clone =="
cp -al "$SRC" "$DST"

echo "== rewriting tbd targets =="
count=0
while IFS= read -r f; do
  if grep -q 'arm64e\.x1-ios' "$f"; then
    sed 's/, *arm64e\.x1-ios//g' "$f" > "$f.rewrite"
    rm -f "$f"
    mv "$f.rewrite" "$f"
    count=$((count+1))
  fi
done < <(find "$DST" -name '*.tbd')
echo "== patched $count tbd files =="
head -4 "$DST/usr/lib/libSystem.tbd"
