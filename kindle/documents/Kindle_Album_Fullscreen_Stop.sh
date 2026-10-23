#!/bin/sh
# Name: Album Fullscreen Stop
# Author: Local album project
# DontUseFBInk
runtime=/tmp/kindle-album-session
app=/mnt/us/kindle-album/fullscreen-v2/app
[ "$(cat "$runtime/project-id" 2>/dev/null)" = kindle-oasis-album-20261022 ] || exit 0
pid=$(cat "$runtime/pid" 2>/dev/null)
case "$pid" in ''|*[!0-9]*) exit 0;; esac
expected_start=$(cat "$runtime/app-start" 2>/dev/null)
[ -n "$expected_start" ] &&
  [ "$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)" = "$expected_start" ] || exit 0
kill -TERM "$pid" 2>/dev/null || :
if [ -f "$runtime/cleanup.sh" ]; then sh "$runtime/cleanup.sh" || :
else sh "$app/cleanup.sh" || :; fi
