#!/bin/sh
# 把 kindle/ 目录里的文件复制到已挂载的 Kindle 数据盘，并放入无线控制用的公钥。
#
# 用法：./install.sh /Volumes/Kindle            首次安装（只新增，不覆盖）
#       ./install.sh --update /Volumes/Kindle   已装过旧版：程序文件先备份再更新
#
# 不会动：书籍、Photos/ 里的照片、已有的相册数据（播放列表、间隔、已导入的照片）。
set -eu

update=0
if [ "${1:-}" = --update ]; then update=1; shift; fi
target=${1:-}
here=$(cd "$(dirname "$0")" && pwd)
src="$here/kindle"
expected_fw='Kindle 5.18.2.1.1 (482111 015)'
key="$HOME/.ssh/kindle_album_ed25519"

die() { printf '✗ %s\n' "$*" >&2; exit 1; }

[ -n "$target" ] || die "请给出 Kindle 数据盘路径，例如：./install.sh /Volumes/Kindle"
[ -d "$target/documents" ] || die "$target 不像 Kindle 数据盘（找不到 documents/）"

fw=$(cat "$target/system/version.txt" 2>/dev/null || true)
[ "$fw" = "$expected_fw" ] || die "固件不符：需要「$expected_fw」，这台是「$fw」。本项目只验证过这一个固件，停止。"
[ -f "$target/koreader/luajit" ] && [ -f "$target/koreader/dropbear" ] ||
  die "没找到 KOReader（koreader/luajit、koreader/dropbear）。请先完成 README 第 3 步。"

command -v ssh-keygen >/dev/null 2>&1 || [ -f "$key" ] || die "找不到 ssh-keygen（macOS 自带；Linux 请装 openssh-client）。"

files=$(cd "$src" && find . -type f ! -name .gitkeep | sed 's|^\./||' | sort)
# 触屏准备已做过的设备不再放回一次性入口
if [ -f "$target/kindle-album/input-ready.txt" ]; then
  files=$(printf '%s\n' $files | grep -v '^documents/Kindle_Album_Input_Setup.sh$')
fi
is_data() { case "$1" in kindle-album/fullscreen-v2/data/*) return 0;; esac; return 1; }

# 第一遍：只检查，不改动
conflicts=""
for f in $files; do
  is_data "$f" && continue                     # 相册数据只在缺失时放入，永不覆盖
  [ -e "$target/$f" ] || continue
  cmp -s "$src/$f" "$target/$f" && continue
  [ "$f" = kindle-album/touch-reader ] && die "Kindle 上的 kindle-album/touch-reader 与本仓库不同，停止。请先查明来源。"
  [ "$f" = kindle-album/project-id ] && die "Kindle 上的 kindle-album/project-id 与本仓库不同，停止。"
  conflicts="$conflicts $f"
done
if [ -n "$conflicts" ] && [ "$update" = 0 ]; then
  for f in $conflicts; do printf '已存在且内容不同：%s\n' "$f" >&2; done
  die "未做任何修改。如果这是本项目的旧版，用：./install.sh --update $target"
fi

# 备份将被替换的旧程序文件
if [ -n "$conflicts" ]; then
  backup="kindle-album/backup/$(date +%Y%m%d-%H%M%S)"
  for f in $conflicts; do
    mkdir -p "$target/$backup/$(dirname "$f")"
    cp "$target/$f" "$target/$backup/$f"
  done
  printf '旧文件已备份到 %s/\n' "$backup"
fi

copied=0
for f in $files; do
  if [ -e "$target/$f" ]; then
    is_data "$f" && continue
    cmp -s "$src/$f" "$target/$f" && continue
  fi
  mkdir -p "$target/$(dirname "$f")"
  cp "$src/$f" "$target/$f.tmp" && mv "$target/$f.tmp" "$target/$f"
  copied=$((copied + 1))
done
mkdir -p "$target/Photos"

# 无线控制公钥：Mac 上生成一次，放到 Kindle；私钥永远只在这台电脑上
if [ ! -f "$key" ]; then
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N '' -C kindle-album -f "$key"
  printf '已生成无线控制密钥：%s\n' "$key"
fi
keys="$target/kindle-album/wireless/authorized_keys"
pub=$(cat "$key.pub")
if ! grep -qxF "$pub" "$keys" 2>/dev/null; then
  printf '%s\n' "$pub" >> "$keys"
  printf '公钥已放入 Kindle。\n'
fi

# macOS 在 FAT 盘上留下的 ._ 文件
find "$target/kindle-album" -name '._*' -type f -exec rm -f {} + 2>/dev/null || :
find "$target/documents" -name '._Kindle_Album*' -type f -exec rm -f {} + 2>/dev/null || :
sync

printf '✓ 更新/新增 %s 个文件。\n' "$copied"
if [ -f "$target/kindle-album/input-ready.txt" ]; then
  printf '下一步：安全弹出 → 拔线 → Kindle 文库点「Album WiFi On」，记下屏幕上的 IP。\n'
else
  printf '下一步：安全弹出 → 拔线 → Kindle 文库点「Album Input Setup」（README 第 5 步）。\n'
fi
