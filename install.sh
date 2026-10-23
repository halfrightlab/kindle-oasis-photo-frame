#!/bin/sh
# 把 kindle/ 目录里的文件复制到已挂载的 Kindle 数据盘。
# 用法：./install.sh /Volumes/Kindle        （macOS）
#       ./install.sh /media/$USER/Kindle    （Linux）
# 只新增文件；遇到同名但内容不同的文件会停下，不覆盖任何东西。
set -eu

target=${1:-}
here=$(cd "$(dirname "$0")" && pwd)
src="$here/kindle"
expected_fw='Kindle 5.18.2.1.1 (482111 015)'

die() { printf '✗ %s\n' "$*" >&2; exit 1; }

[ -n "$target" ] || die "请给出 Kindle 数据盘路径，例如：./install.sh /Volumes/Kindle"
[ -d "$target/documents" ] || die "$target 不像 Kindle 数据盘（找不到 documents/）"

fw=$(cat "$target/system/version.txt" 2>/dev/null || true)
[ "$fw" = "$expected_fw" ] || die "固件不符：需要「$expected_fw」，这台是「$fw」。本项目只验证过这一个固件，停止。"

[ -x "$target/koreader/luajit" ] || [ -f "$target/koreader/luajit" ] ||
  die "没找到 koreader/luajit。请先完成 README 第 2 步（安装 KOReader）。"

# 第一遍：只检查冲突
conflicts=0
for f in $(cd "$src" && find . -type f ! -name .gitkeep | sed 's|^\./||'); do
  if [ -e "$target/$f" ] && ! cmp -s "$src/$f" "$target/$f"; then
    printf '冲突（已存在且内容不同）：%s\n' "$f" >&2
    conflicts=$((conflicts + 1))
  fi
done
[ "$conflicts" -eq 0 ] || die "有 $conflicts 个冲突文件，未做任何修改。先备份/移走它们再重试。"

# 第二遍：复制
copied=0; same=0
for f in $(cd "$src" && find . -type f ! -name .gitkeep | sed 's|^\./||'); do
  if [ -e "$target/$f" ]; then same=$((same + 1)); continue; fi
  mkdir -p "$target/$(dirname "$f")"
  cp "$src/$f" "$target/$f"
  copied=$((copied + 1))
done
mkdir -p "$target/Photos"
# macOS 会在 FAT 盘上留下 ._ 文件，清掉本项目目录里的
find "$target/kindle-album" "$target/documents" -name '._Kindle_Album*' -type f -delete 2>/dev/null || :
find "$target/kindle-album" -name '._*' -type f -delete 2>/dev/null || :
sync

printf '✓ 新复制 %s 个文件，%s 个已存在且相同。\n' "$copied" "$same"
printf '下一步：安全弹出 Kindle → 拔线 → 在文库打开「Album Input Setup」（README 第 4 步）。\n'
