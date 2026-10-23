#!/bin/sh
set -u
runtime=/tmp/kindle-album-session
app=/mnt/us/kindle-album/fullscreen-v2/app
base=/mnt/us/kindle-album/fullscreen-v2/data
touch_binary=/var/local/kindle-album/app/touch-reader
[ -f "$runtime/project-id" ] || exit 0
[ "$(cat "$runtime/project-id")" = kindle-oasis-album-20261022 ] || exit 79
mkdir "$runtime/cleanup.lock" 2>/dev/null || exit 0
log=/mnt/us/kindle-album/fullscreen-v2/data/session.log
phase=$(cat "$runtime/power-phase" 2>/dev/null || printf active)
if [ ! -r "$base/project-id" ] ||
   [ "$(cat "$base/project-id" 2>/dev/null)" != kindle-oasis-album-20261022 ]; then phase=usb; fi
resume_window_manager() {
  wm_resumed=not_paused
  [ -f "$runtime/wm-paused" ] || return 0
  wm_resumed=no
  wm_pid=$(cat "$runtime/wm-pid" 2>/dev/null || :)
  wm_exe=$(cat "$runtime/wm-exe" 2>/dev/null || :)
  wm_start=$(cat "$runtime/wm-start" 2>/dev/null || :)
  case "$wm_exe" in
    /usr/bin/awesome|/usr/sbin/awesome)
      if [ -n "$wm_start" ] &&
         [ "$(readlink "/proc/$wm_pid/exe" 2>/dev/null)" = "$wm_exe" ] &&
         [ "$(awk '{print $22}' "/proc/$wm_pid/stat" 2>/dev/null)" = "$wm_start" ]; then
        if kill -CONT "$wm_pid" 2>/dev/null; then wm_resumed=yes; fi
      fi;;
  esac
}
# USB owns the screen. Restore native event handling before any slow query,
# graphics operation or wait for a misbehaving input reader.
if [ "$phase" = usb ]; then resume_window_manager; fi
import_owned() {
  [ -n "$import_start" ] &&
    [ "$(readlink "/proc/$import_pid/exe" 2>/dev/null)" = /mnt/us/koreader/luajit ] &&
    [ "$(awk '{print $22}' "/proc/$import_pid/stat" 2>/dev/null)" = "$import_start" ]
}
if [ -f "$runtime/import-pid" ]; then
  import_pid=$(cat "$runtime/import-pid")
  import_start=$(cat "$runtime/import-start" 2>/dev/null || :)
  if import_owned; then
    kill -TERM "$import_pid" 2>/dev/null || :
    n=0
    while import_owned && [ "$n" -lt 3 ]; do sleep 1; n=$((n+1)); done
    if import_owned; then kill -KILL "$import_pid" 2>/dev/null || :; fi
  fi
fi
touch_owned() {
  [ -n "$touch_start" ] &&
    [ "$(readlink "/proc/$touch_pid/exe" 2>/dev/null)" = "$touch_binary" ] &&
    [ "$(awk '{print $22}' "/proc/$touch_pid/stat" 2>/dev/null)" = "$touch_start" ]
}
if [ -f "$runtime/power-pid" ] && [ -f "$runtime/power-start" ]; then
  pid=$(cat "$runtime/power-pid")
  expected_start=$(cat "$runtime/power-start")
  actual_start=$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || :)
  if [ -n "$expected_start" ] && [ "$actual_start" = "$expected_start" ]; then
    case "$(readlink "/proc/$pid/exe" 2>/dev/null)" in
      */lipc-wait-event) kill -TERM "$pid" 2>/dev/null || :;;
    esac
  fi
fi
if [ -f "$runtime/touch-pid" ]; then
  touch_pid=$(cat "$runtime/touch-pid")
  touch_start=$(cat "$runtime/touch-start" 2>/dev/null || :)
  if touch_owned; then
    kill -TERM "$touch_pid" 2>/dev/null || :
    n=0
    while touch_owned && [ "$n" -lt 3 ]; do sleep 1; n=$((n+1)); done
    if touch_owned; then kill -KILL "$touch_pid" 2>/dev/null || :; fi
  fi
fi
restored=no
if [ "$phase" = usb ]; then
  restored=skipped_usb
else
  native_state=$(timeout 3 lipc-get-prop com.lab126.powerd state 2>/dev/null || printf unavailable)
  if [ "$phase" != active ] || [ "$native_state" != active ] || [ -f /var/local/system/userpasswdenabled ]; then
    # A pre-lock snapshot must never replace the stock lock/password screen.
    restored=skipped_native_lock
  elif [ -f "$runtime/native.raw" ]; then
    expected=$(sha256sum "$runtime/native.raw" | cut -d ' ' -f 1)
    attempt=0
    while [ "$attempt" -lt 3 ]; do
      attempt=$((attempt+1))
      if dd if="$runtime/native.raw" of=/dev/fb0 bs=1280 count=1680 conv=notrunc 2>/dev/null; then
        observed=$(dd if=/dev/fb0 bs=1280 count=1680 2>/dev/null | sha256sum | cut -d ' ' -f 1)
        # Check bytes before requesting an e-paper update; the native display
        # service may legitimately modify its working buffer during a refresh.
        if [ "$expected" = "$observed" ] && /usr/sbin/eips -s w=1264,h=1680 -f >/dev/null 2>&1; then
          restored=yes
          break
        fi
      fi
    done
  fi
fi
if [ -f "$runtime/cvm-paused" ] && [ -f "$runtime/cvm-pid" ]; then
  pid=$(cat "$runtime/cvm-pid")
  if [ "$(readlink "/proc/$pid/exe" 2>/dev/null)" = /usr/java/bin/cvm ]; then kill -CONT "$pid" 2>/dev/null || :; fi
fi
if [ "$phase" != usb ]; then resume_window_manager; fi
sleep_restored=already_restored
if [ -f "$runtime/powerd-before" ]; then
  before=$(cat "$runtime/powerd-before")
  case "$before" in 0|1) if lipc-set-prop com.lab126.powerd preventScreenSaver "$before"; then sleep_restored=yes; fi;; esac
fi
touch_released=yes
if [ -f "$runtime/touch-pid" ]; then
  if touch_owned; then touch_released=no; fi
fi
printf 'exit_native_restored=%s\nexit_touch_released=%s\nexit_sleep_restored=%s\n' "$restored" "$touch_released" "$sleep_restored" >> "$log"
printf 'exit_window_manager_resumed=%s\n' "$wm_resumed" >> "$log"
case "$restored" in yes|skipped_native_lock|skipped_usb) rm -f "$runtime/native.raw";; esac
# Keep a failed snapshot private for recovery; never export it to the Mac.
rm -f "$runtime/pid" "$runtime/touch-pid" "$runtime/touch-start" "$runtime/cvm-pid" "$runtime/cvm-paused" "$runtime/powerd-before" "$runtime/heartbeat" "$runtime/events" "$runtime/frame-state" "$runtime/native.raw.tmp" "$runtime/power-pid" "$runtime/power-start" "$runtime/power-phase" "$runtime/power-errors"
rm -f "$runtime/wm-pid" "$runtime/wm-exe" "$runtime/wm-start" "$runtime/wm-paused" "$runtime/power-query-error"
rm -f "$runtime/sleep-sample.raw" "$runtime/event-sources" "$runtime/cleanup.sh" "$runtime/watchdog.sh" "$runtime/cleanup.sh.tmp" "$runtime/watchdog.sh.tmp"
rm -f "$runtime/album.sh" "$runtime/ui-state.sh" "$runtime/power-state.sh" "$runtime/album.sh.tmp" "$runtime/ui-state.sh.tmp" "$runtime/power-state.sh.tmp" "$runtime/app-start" "$runtime/launch.log"
rm -f "$runtime/photo-import.sh" "$runtime/photo-import.sh.tmp" "$runtime/photo-import.lua" "$runtime/photo-import.lua.tmp"
rm -f "$runtime/import-pid" "$runtime/import-start" "$runtime/import-log" "$runtime/import-original" "$runtime/import-original.tmp" "$runtime/import-pending" "$runtime/import-pending.tmp"
rm -f "$runtime/import-progress" "$runtime/import-progress.tmp" "$runtime/import-result" "$runtime/import-result.tmp" "$runtime/import-ready" "$runtime/import-ready.tmp"
if [ ! -f "$runtime/native.raw" ]; then rm -f "$runtime/project-id"; fi
rmdir "$runtime/cleanup.lock" 2>/dev/null || :
rmdir "$runtime" 2>/dev/null || :
sync
