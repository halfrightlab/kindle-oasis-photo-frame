#!/bin/sh
# Name: Album Fullscreen
# Author: Local album project
# DontUseFBInk
base=/mnt/us/kindle-album/fullscreen-v2
# 已开启无线控制时，顺带确保 SSH 在线（失败不影响相册）
[ -f /var/local/kindle-album/ssh/autostart ] && sh /mnt/us/kindle-album/wireless/ssh-on.sh quiet >/dev/null 2>&1
exec sh "$base/app/album.sh" > "$base/launch.log" 2>&1
