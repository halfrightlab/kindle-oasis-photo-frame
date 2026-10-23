#!/bin/sh
# Name: Album Input Setup
# Author: Local album project
# DontUseFBInk
# One-time preparation only. Does not start the album or acquire input.
set -eu
[ "$(id -u)" = 0 ] || exit 77
[ "$(cat /mnt/us/system/version.txt)" = 'Kindle 5.18.2.1.1 (482111 015)' ] || exit 78
[ "$(cat /mnt/us/kindle-album/project-id)" = kindle-oasis-album-20261022 ] || exit 79
[ "$(cat /sys/class/graphics/fb0/bits_per_pixel)" = 8 ] || exit 81
[ "$(cat /sys/class/graphics/fb0/rotate)" = 0 ] || exit 82
[ -r /dev/input/event8 ] || exit 83
source=/mnt/us/kindle-album/touch-reader
target=/var/local/kindle-album/app/touch-reader
expected=aea0e2ce863b166654b7a9ff7122d1734d18856d5a864f259ffe8c801c56ddf7
[ ! -L "$source" ] && [ -f "$source" ] || exit 84
printf '%s  %s\n' "$expected" "$source" | sha256sum -c - >/dev/null || exit 85
if [ -e "$target" ] || [ -L "$target" ]; then
  [ ! -L "$target" ] && [ -f "$target" ] && [ -x "$target" ] || exit 86
  printf '%s  %s\n' "$expected" "$target" | sha256sum -c - >/dev/null || exit 86
else
  mkdir -p /var/local/kindle-album/app
  temporary="$target.setup-$$"
  [ ! -e "$temporary" ] || exit 87
  trap 'rm -f "$temporary"' EXIT
  trap 'exit 1' HUP INT TERM
  cp "$source" "$temporary"
  printf '%s  %s\n' "$expected" "$temporary" | sha256sum -c - >/dev/null || exit 85
  chmod 755 "$temporary"
  mv "$temporary" "$target"
fi
printf 'input_helper_ready=yes\ninput_helper_sha256=%s\n' "$expected" > /mnt/us/kindle-album/input-ready.txt
sync
