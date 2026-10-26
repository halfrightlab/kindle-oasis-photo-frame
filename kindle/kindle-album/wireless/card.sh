#!/bin/sh
# 全屏显示无线控制的结果，轻点屏幕关闭（最长 2 分钟；屏幕休眠、插 USB 时也会关闭）。
# 用法：sh card.sh "第一行" ["第二行"]
# 做不到全屏时（缺触屏读取器或 fbink、相册在运行、不是亮屏）退回原来的 eips 一行提示。
set -u
# shell 边运行边读脚本；插 USB 时 /mnt/us 会被卸载，所以先换到 /tmp 的副本运行
if [ "$0" != /tmp/kindle-album-card.sh ] &&
   cp "$0" /tmp/kindle-album-card.sh.tmp 2>/dev/null && mv /tmp/kindle-album-card.sh.tmp /tmp/kindle-album-card.sh; then
  exec sh /tmp/kindle-album-card.sh "$@"
fi
title=$1
detail=${2:-}
touch_binary=/var/local/kindle-album/app/touch-reader
fbink=/mnt/us/koreader/fbink
work=/tmp/kindle-album-card
limit=120

fallback() {
  /usr/sbin/eips 1 5 "$title  $detail                    " >/dev/null 2>&1 || :
  exit 0
}

[ -x "$touch_binary" ] && [ -x "$fbink" ] || fallback
[ ! -e /tmp/kindle-album-session ] || fallback
[ "$(timeout 3 lipc-get-prop com.lab126.powerd state 2>/dev/null)" = active ] || fallback
[ "$(cat /sys/class/graphics/fb0/bits_per_pixel)" = 8 ] && [ "$(cat /sys/class/graphics/fb0/rotate)" = 0 ] || fallback
wm_pid=$(pidof awesome)
case "$wm_pid" in ''|*[!0-9]*) fallback;; esac

# 同时只开一张；上一张若已异常退出，清掉它留下的目录
if ! mkdir "$work" 2>/dev/null; then
  old=$(cat "$work/pid" 2>/dev/null || :)
  case "$old" in ''|*[!0-9]*) :;; *) kill -0 "$old" 2>/dev/null && fallback;; esac
  rm -rf "$work"
  mkdir "$work" || fallback
fi
echo $$ > "$work/pid"

touch_pid=
paused=0
restore() {
  if [ -n "$touch_pid" ]; then kill -TERM "$touch_pid" 2>/dev/null || :; wait "$touch_pid" 2>/dev/null || :; fi
  if [ -f "$work/native.raw" ]; then
    dd if="$work/native.raw" of=/dev/fb0 bs=1280 count=1680 conv=notrunc 2>/dev/null || :
  fi
  if [ "$paused" = 1 ]; then kill -CONT "$wm_pid" 2>/dev/null || :; fi
  /usr/sbin/eips -s w=1264,h=1680 -f >/dev/null 2>&1 || :
  rm -rf "$work"
}
trap restore EXIT
trap 'exit 0' HUP INT TERM

# 先拿到触屏（独占，文库收不到这次点击），再暂停系统界面，免得它盖掉画面
mkfifo "$work/events" || exit 0
exec 3<> "$work/events"
"$touch_binary" > "$work/events" &
touch_pid=$!
ready=
for _ in 1 2 3; do
  if IFS= read -r -t 1 line <&3 && [ "$line" = READY ]; then ready=1; break; fi
done
[ -n "$ready" ] || { restore; trap - EXIT; fallback; }

dd if=/dev/fb0 of="$work/native.raw" bs=1280 count=1680 2>/dev/null
[ "$(wc -c < "$work/native.raw" | tr -d ' ')" = 2150400 ] || { rm -f "$work/native.raw"; exit 0; }
kill -STOP "$wm_pid" || exit 0
paused=1

"$fbink" -q -k -f >/dev/null 2>&1
"$fbink" -q -M -m -y -5 -S 4 "$title" >/dev/null 2>&1
[ -z "$detail" ] || "$fbink" -q -M -m -y 0 -S 6 "$detail" >/dev/null 2>&1
"$fbink" -q -M -m -y 10 -S 3 "Tap anywhere to close" >/dev/null 2>&1

deadline=$(($(date +%s)+limit))
down=0
released=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  kill -0 "$touch_pid" 2>/dev/null || exit 0
  [ "$(timeout 3 lipc-get-prop com.lab126.powerd state 2>/dev/null)" = active ] || exit 0
  [ -r /mnt/us/kindle-album/project-id ] || exit 0
  IFS=' ' read -r -t 1 type code value <&3 || continue
  case "$type:$code" in
    0003:0039)
      if [ "$value" = ffffffff ]; then [ "$down" = 0 ] || released=1; down=0; else down=1; fi;;
    0001:014a)
      if [ "$value" = 00000000 ]; then [ "$down" = 0 ] || released=1; down=0; else down=1; fi;;
    0000:0000)
      [ "$released" = 0 ] || exit 0;;
  esac
done
exit 0
