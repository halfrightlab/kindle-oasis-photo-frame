#!/bin/sh
set -eu
ulimit -c 0
app=/mnt/us/kindle-album/fullscreen-v2/app
touch_binary=/var/local/kindle-album/app/touch-reader
base=/mnt/us/kindle-album/fullscreen-v2/data
runtime=/tmp/kindle-album-session
if [ "$0" = "$runtime/album.sh" ]; then
  [ "$(cat "$runtime/project-id")" = kindle-oasis-album-20261022 ] &&
    [ "$(cat "$runtime/pid")" = "$$" ] || exit 80
  # Exec drops the bootstrap trap. A USB/PIN change during revalidation must
  # still remove the owned session before input or the WM has been acquired.
  trap 'sh "$runtime/cleanup.sh" || :' EXIT
fi
[ "$(id -u)" = 0 ] || exit 77
# This sleep trial has no verified native PIN event trace. Refuse before
# taking input or pausing the native UI; never change the password flag.
if [ -f /var/local/system/userpasswdenabled ]; then
  printf 'Sleep trial requires the native PIN flow to be validated; no input or setting changed.\n' >&2
  exit 96
fi
[ -x "$touch_binary" ] || exit 94
printf '%s  %s\n' 'aea0e2ce863b166654b7a9ff7122d1734d18856d5a864f259ffe8c801c56ddf7' "$touch_binary" | sha256sum -c - >/dev/null || exit 95
[ "$(cat "$base/project-id")" = kindle-oasis-album-20261022 ] || exit 79
[ "$0" = "$runtime/album.sh" ] || [ ! -e "$runtime" ] || exit 80
[ "$(cat /sys/class/graphics/fb0/bits_per_pixel)" = 8 ] || exit 81
[ "$(cat /sys/class/graphics/fb0/rotate)" = 0 ] || exit 82
count=$(wc -l < "$base/slides.txt" | tr -d ' ')
[ "$count" -gt 0 ] && [ "$count" -le 500 ] || exit 83
while IFS= read -r prefix; do
  case "$prefix" in ''|*[!A-Za-z0-9_-]*) exit 84;; esac
  for layout in crop contain; do
    for variant in clean 10 30 60 300; do
      [ -f "$base/assets/$prefix-$layout-$variant.png" ] || exit 85
    done
  done
done < "$base/slides.txt"
interval=$(cat "$base/interval.txt")
case "$interval" in 10|30|60|300) :;; *) exit 86;; esac
fit_mode=crop
if [ -f "$base/mode.txt" ]; then fit_mode=$(cat "$base/mode.txt"); fi
case "$fit_mode" in crop|contain) :;; *) exit 93;; esac
wm_pid=$(pidof awesome)
case "$wm_pid" in ''|*[!0-9]*) printf 'Expected one native window manager process.\n' >&2; exit 87;; esac
wm_exe=$(readlink "/proc/$wm_pid/exe")
case "$wm_exe" in /usr/bin/awesome|/usr/sbin/awesome) :;; *) printf 'Unexpected window manager executable: %s\n' "$wm_exe" >&2; exit 88;; esac
wm_start=$(awk '{print $22}' "/proc/$wm_pid/stat")
case "$wm_start" in ''|*[!0-9]*) exit 88;; esac
umask 077
if [ "$0" != "$runtime/album.sh" ]; then
  # Load recovery before creating the session: even a partial helper-copy
  # failure after USB export must not leave a session that blocks relaunch.
  bootstrap_cleanup=$(cat "$app/cleanup.sh") || exit 101
  mkdir "$runtime"
  printf '%s\n' "$bootstrap_cleanup" > "$runtime/cleanup.sh"
fi
printf 'kindle-oasis-album-20261022\n' > "$runtime/project-id"
printf '%s\n' "$$" > "$runtime/pid"
awk '{print $22}' "/proc/$$/stat" > "$runtime/app-start"
printf '%s\n' "$wm_pid" > "$runtime/wm-pid"
printf '%s\n' "$wm_exe" > "$runtime/wm-exe"
printf '%s\n' "$wm_start" > "$runtime/wm-start"
date +%s > "$runtime/heartbeat"
exit_signal=none
finish_album() {
  trap - EXIT
  {
    printf 'app_exit_status=%s signal=%s phase=%s time=%s\n' "$1" "$exit_signal" "${power_phase-starting}" "$(date +%s)"
    if [ -s "$runtime/power-errors" ]; then
      printf 'event_listener_errors_begin\n'
      head -n 10 "$runtime/power-errors"
      printf 'event_listener_errors_end\n'
    fi
  } >> "$base/session.log" || :
  if [ -f "$runtime/launch.log" ] && [ -d "$base" ]; then
    cp "$runtime/launch.log" "$base/../launch.log" 2>/dev/null || :
  fi
  sh "$cleanup_script" || :
  exit "$1"
}
cleanup_script="$runtime/cleanup.sh"
trap 'finish_album "$?"' EXIT
trap 'exit_signal=HUP; exit 0' HUP
trap 'exit_signal=INT; exit 0' INT
trap 'exit_signal=TERM; exit 0' TERM
printf 'started=%s\nversion=fullscreen-v2-device-photo-import1\ninterval=%s\nmode=%s\nnetwork_required=no\nsleep_adaptation=trial_requires_native_exit\npasscode_policy=refuse_if_enabled\npower_settings_modified=no\nnative_framework_paused=no\n' "$(date +%s)" "$interval" "$fit_mode" > "$base/session.log"
cache_session_helpers() {
  for helper in cleanup watchdog album ui-state power-state photo-import; do
    cp "$app/$helper.sh" "$runtime/$helper.sh.tmp" || return 1
    mv "$runtime/$helper.sh.tmp" "$runtime/$helper.sh" || return 1
  done
  cp "$app/photo-import.lua" "$runtime/photo-import.lua.tmp" || return 1
  mv "$runtime/photo-import.lua.tmp" "$runtime/photo-import.lua" || return 1
}
if [ "$0" != "$runtime/album.sh" ]; then
  cache_session_helpers || exit 101
  # A shell may still read its script after startup. Keep the whole session,
  # including its diagnostics FD, independent of the exported USB filesystem.
  exec sh "$runtime/album.sh" > "$runtime/launch.log" 2>&1
fi
cleanup_script="$runtime/cleanup.sh"
. "$runtime/ui-state.sh"
. "$runtime/power-state.sh"
. "$runtime/photo-import.sh"
nohup sh "$runtime/watchdog.sh" "$$" >/dev/null 2>&1 < /dev/null &
before=$(lipc-get-prop com.lab126.powerd preventScreenSaver)
case "$before" in 0) :;; *) exit 89;; esac
mkfifo "$runtime/events"
exec 3<> "$runtime/events"
usb_handoff() {
  power_phase=usb
  printf 'usb\n' > "$runtime/power-phase"
  printf 'usb_handoff=yes time=%s\n' "$(date +%s)" >> "$base/session.log" || :
}
require_media() {
  if [ ! -r "$base/project-id" ] ||
     [ "$(cat "$base/project-id" 2>/dev/null)" != kindle-oasis-album-20261022 ]; then
    usb_handoff
    exit 0
  fi
}
touch_start() {
  require_media
  "$touch_binary" > "$runtime/events" &
  touch_pid=$!
  printf '%s\n' "$touch_pid" > "$runtime/touch-pid"
  awk '{print $22}' "/proc/$touch_pid/stat" > "$runtime/touch-start"
  ready_until=$(($(date +%s)+3))
  while [ "$(date +%s)" -le "$ready_until" ]; do
    if IFS= read -r -t 1 ready <&3; then
      case "$ready" in
        READY) return 0;;
        *usbConfigured*|*userstoreUnAvailable*) usb_handoff; exit 0;;
        *goingToScreenSaver*|*goingToPasswdDlg*|*readyToSuspend*) return 1;;
      esac
    fi
  done
  return 1
}
touch_stop() {
  [ -f "$runtime/touch-pid" ] || return 0
  touch_pid=$(cat "$runtime/touch-pid")
  touch_start_time=$(cat "$runtime/touch-start")
  if [ "$(readlink "/proc/$touch_pid/exe" 2>/dev/null)" = "$touch_binary" ] &&
     [ "$(awk '{print $22}' "/proc/$touch_pid/stat" 2>/dev/null)" = "$touch_start_time" ]; then
    kill -TERM "$touch_pid" 2>/dev/null || :
    touch_wait=0
    while [ "$(readlink "/proc/$touch_pid/exe" 2>/dev/null)" = "$touch_binary" ] && [ "$touch_wait" -lt 3 ]; do
      sleep 1; touch_wait=$((touch_wait+1))
    done
    if [ "$(readlink "/proc/$touch_pid/exe" 2>/dev/null)" = "$touch_binary" ] &&
       [ "$(awk '{print $22}' "/proc/$touch_pid/stat" 2>/dev/null)" = "$touch_start_time" ]; then
      kill -KILL "$touch_pid" 2>/dev/null || :
    fi
    wait "$touch_pid" 2>/dev/null || :
  fi
  [ "$(readlink "/proc/$touch_pid/exe" 2>/dev/null)" != "$touch_binary" ] || return 1
  rm -f "$runtime/touch-pid" "$runtime/touch-start"
}
snapshot_native() {
  dd if=/dev/fb0 of="$runtime/native.raw.tmp" bs=1280 count=1680 2>/dev/null
  [ "$(wc -c < "$runtime/native.raw.tmp" | tr -d ' ')" = 2150400 ] || return 1
  mv "$runtime/native.raw.tmp" "$runtime/native.raw"
}
wm_verify() {
  [ "$(readlink "/proc/$wm_pid/exe" 2>/dev/null)" = "$wm_exe" ] &&
    [ "$(awk '{print $22}' "/proc/$wm_pid/stat" 2>/dev/null)" = "$wm_start" ]
}
wm_pause() {
  wm_verify || return 1
  printf 'paused\n' > "$runtime/wm-paused"
  kill -STOP "$wm_pid"
}
wm_resume() {
  [ -f "$runtime/wm-paused" ] || return 0
  wm_verify || return 1
  kill -CONT "$wm_pid" || return 1
  rm -f "$runtime/wm-paused"
}
get_power_state() {
  if state_value=$(timeout 3 lipc-get-prop com.lab126.powerd state 2> "$runtime/power-query-error"); then
    printf '%s\n' "$state_value"
  else
    state_status=$?
    printf 'power_query_failed_status=%s time=%s\n' "$state_status" "$(date +%s)" >> "$base/session.log"
    printf 'unavailable\n'
  fi
}
frame_fingerprint() {
  # Private RAM-only sample. Never log or export native framebuffer bytes.
  dd if=/dev/fb0 of="$runtime/sleep-sample.raw" bs=1280 count=1680 2>/dev/null || return 1
  [ "$(wc -c < "$runtime/sleep-sample.raw" | tr -d ' ')" = 2150400 ] || return 1
  sample_hash=$(sha256sum "$runtime/sleep-sample.raw" | cut -d ' ' -f 1)
  rm -f "$runtime/sleep-sample.raw"
  [ "${#sample_hash}" = 64 ] || return 1
  printf '%s\n' "$sample_hash"
}
settle_sleep_frame() {
  previous_frame=
  sample_number=0
  while [ "$sample_number" -lt 3 ]; do
    [ ! -f /var/local/system/userpasswdenabled ] || return 1
    case "$(get_power_state)" in screenSaver|readyToSuspend) :;; *) return 1;; esac
    sampled_frame=$(frame_fingerprint) || return 1
    [ "$sampled_frame" != "$previous_frame" ] || return 0
    previous_frame=$sampled_frame
    sample_number=$((sample_number+1))
    if [ "$sample_number" -lt 3 ]; then sleep 1; fi
  done
  return 1
}
power_init
printf 'starting\n' > "$runtime/power-phase"
printf 'com.lab126.powerd\ncom.lab126.hal\ncom.lab126.volumd\n' > "$runtime/event-sources"
lipc-wait-event -m -t -l '*' < "$runtime/event-sources" > "$runtime/events" 2> "$runtime/power-errors" &
power_pid=$!
printf '%s\n' "$power_pid" > "$runtime/power-pid"
awk '{print $22}' "/proc/$power_pid/stat" > "$runtime/power-start"
touch_start || exit 90
[ "$(get_power_state)" = active ] || exit 97
snapshot_native || exit 92
wm_pause || exit 100
printf 'active\n' > "$runtime/power-phase"
index=1
x=0; y=0; slot=0; down=0; released=0
ui_init "$(date +%s)"
photo_import_start
yield_native() {
  printf '%s\n' "$power_phase" > "$runtime/power-phase"
  controls_visible=0; render_needed=0
  touch_stop
  wm_resume || return 1
  x=0; y=0; slot=0; down=0; released=0
  printf 'lock_native_resumed=yes\nlock_touch_released=yes\n' >> "$base/session.log"
  power_yield=0
}
resume_album() {
  require_media
  [ ! -f /var/local/system/userpasswdenabled ] || return 1
  [ "$native_exit_seen" = 1 ] || return 1
  [ "$(get_power_state)" = active ] || return 1
  wm_verify || return 1
  printf 'resuming\n' > "$runtime/power-phase"
  snapshot_native || return 1
  touch_start || return 1
  [ "$(get_power_state)" = active ] || return 1
  [ ! -f /var/local/system/userpasswdenabled ] || return 1
  wm_pause || return 1
  power_init
  printf 'active\n' > "$runtime/power-phase"
  last_image_path=
  ui_init "$(date +%s)"
  printf 'resume_after_native_exit=yes\nresume_frame=%s\n' "$index" >> "$base/session.log"
}
render() {
  require_media
  [ ! -f /var/local/system/userpasswdenabled ] || return 1
  render_state=$(get_power_state)
  if [ "$power_phase" = active ]; then
    if [ "$render_state" != active ]; then
      power_tick "$render_state" "$(date +%s)"
      yield_native
      [ "$power_abort" = 0 ] || return 1
      return 0
    fi
  else
    [ "$power_phase" = locked ] || return 0
    case "$render_state" in
      screenSaver)
        if ! settle_sleep_frame; then return 0; fi;;
      readyToSuspend) :;;
      *) return 0;;
    esac
    [ ! -f /var/local/system/userpasswdenabled ] || return 1
    case "$(get_power_state)" in screenSaver|readyToSuspend) :;; *) return 0;; esac
  fi
  prefix=$(sed -n "${index}p" "$base/slides.txt")
  variant=clean
  if [ "$controls_visible" = 1 ]; then variant=$interval; fi
  display=photo
  image_path="$base/assets/$prefix-$fit_mode-$variant.png"
  if [ "$power_phase" = active ] && [ "$controls_visible" = 0 ]; then
    case "${photo_import_status-idle}" in
      working|warning)
        display=$photo_import_status
        image_path="$app/import-ui/$display.png";;
    esac
  fi
  if [ "$display" != photo ] && [ "$image_path" = "${last_image_path-}" ]; then
    render_needed=0
    return 0
  fi
  /usr/sbin/eips -g "$image_path" -w gc16 -f -x 0 -y 0 >/dev/null 2>&1 || return 1
  last_image_path=$image_path
  require_media
  now=$(date +%s)
  if [ "$display" = photo ]; then
    printf 'frame=%s interval=%s mode=%s controls=%s time=%s power_phase=%s\n' "$index" "$interval" "$fit_mode" "$controls_visible" "$now" "$power_phase" >> "$base/session.log"
  else
    printf 'import_screen=%s time=%s power_phase=%s\n' "$display" "$now" "$power_phase" >> "$base/session.log"
  fi
  if [ "$power_phase" = locked ]; then
    if [ "$sleep_photo_drawn" = 0 ]; then sleep_photo_guard_until=$((now+5)); fi
    sleep_photo_drawn=1
    sleep_photo_fingerprint=$(frame_fingerprint) || sleep_photo_fingerprint=
    printf 'sleep_photo_drawn=yes\n' >> "$base/session.log"
  fi
  printf '%s %s %s %s\n' "$index" "$interval" "$fit_mode" "$controls_visible" > "$runtime/frame-state"
  render_needed=0
}
check_sleep_photo() {
  [ "$power_phase" = locked ] && [ "$sleep_photo_drawn" = 1 ] &&
    [ -n "$sleep_photo_fingerprint" ] && [ "$sleep_photo_repairs" -lt 2 ] || return 0
  if [ "$1" != 1 ] && [ "$(date +%s)" -gt "$sleep_photo_guard_until" ]; then return 0; fi
  observed_frame=$(frame_fingerprint) || return 0
  if [ "$observed_frame" != "$sleep_photo_fingerprint" ]; then
    sleep_photo_repairs=$((sleep_photo_repairs+1))
    printf 'sleep_photo_overwrite_detected=yes repair=%s time=%s\n' "$sleep_photo_repairs" "$(date +%s)" >> "$base/session.log"
    render
  fi
}
render
last_power_check=0
last_power_state=
while :; do
  require_media
  if ! kill -0 "$power_pid" 2>/dev/null; then
    listener_status=0
    wait "$power_pid" || listener_status=$?
    printf 'event_listener_exited_status=%s time=%s\n' "$listener_status" "$(date +%s)" >> "$base/session.log"
    exit 98
  fi
  date +%s > "$runtime/heartbeat"
  force_power_check=0
  force_sleep_check=0
  if IFS= read -r -t 1 event_line <&3; then
    case "$event_line" in
      *usbConfigured*|*userstoreUnAvailable*) usb_handoff; exit 0;;
      *goingToScreenSaver*|*readyToSuspend*|*wakeupFromSuspend*|*outOfScreenSaver*|*exitingScreenSaver*|*goingToPasswdDlg*)
        printf 'power_event=%s\n' "$event_line" >> "$base/session.log"
        power_event "$event_line" "$(date +%s)"
        case "$event_line" in *readyToSuspend*) force_sleep_check=1;; esac
        force_power_check=1;;
      *)
        if [ "$power_phase" = active ]; then
          IFS=' ' read -r event_type event_code hex_value <<EOF
$event_line
EOF
          case "$event_type:$event_code" in
      0003:002f) slot=$((0x$hex_value));;
      0003:0035) [ "$slot" != 0 ] || x=$((0x$hex_value));;
      0003:0036) [ "$slot" != 0 ] || y=$((0x$hex_value));;
      0003:0039)
        if [ "$slot" = 0 ]; then
          if [ "$hex_value" = ffffffff ]; then [ "$down" = 0 ] || released=1; down=0; else down=1; fi
        fi;;
      0001:014a)
        if [ "$hex_value" = 00000000 ]; then [ "$down" = 0 ] || released=1; down=0; else down=1; fi;;
      0000:0000)
        if [ "$released" = 1 ]; then
          released=0
          if [ "$photo_import_status" = warning ]; then photo_import_status=idle; render_needed=1; fi
          ui_tap "$x" "$y" "$(date +%s)"
          if [ "$wants_exit" = 1 ]; then printf 'exit_button=yes\n' >> "$base/session.log"; exit 0; fi
          if [ "$persist_interval" = 1 ]; then printf '%s\n' "$interval" > "$base/interval.txt"; persist_interval=0; fi
          if [ "$persist_mode" = 1 ]; then printf '%s\n' "$fit_mode" > "$base/mode.txt"; persist_mode=0; fi
        fi;;
          esac
        fi;;
    esac
  fi
  now=$(date +%s)
  if [ "$force_power_check" = 1 ] || [ "$now" != "$last_power_check" ]; then
    power_state=$(get_power_state)
    # The query may return only after a real suspend. Use the wake-time clock
    # when creating the native-exit grace, never the pre-query timestamp.
    now=$(date +%s)
    power_tick "$power_state" "$now"
    if [ "$power_state" != "$last_power_state" ]; then
      suspend_count=unavailable
      if [ -r /sys/power/suspend_stats/success ]; then suspend_count=$(cat /sys/power/suspend_stats/success)
      elif [ -r /sys/kernel/debug/suspend_stats ]; then suspend_count=$(awk '/^success:/ {print $2; exit}' /sys/kernel/debug/suspend_stats)
      fi
      printf 'power_state=%s suspend_success=%s time=%s\n' "$power_state" "$suspend_count" "$(date +%s)" >> "$base/session.log"
      last_power_state=$power_state
    fi
    last_power_check=$now
  fi
  if [ "$power_yield" = 1 ]; then yield_native; fi
  if [ "$power_abort" = 1 ]; then printf 'native_fallback=yes\n' >> "$base/session.log"; exit 0; fi
  if [ "$power_photo" = 1 ]; then render; power_photo=0; fi
  check_sleep_photo "$force_sleep_check"
  if [ "$power_resume" = 1 ]; then resume_album || exit 99; fi
  if [ "$power_phase" = active ]; then
    [ "$(readlink "/proc/$touch_pid/exe" 2>/dev/null)" = "$touch_binary" ] || exit 91
    photo_import_poll
    ui_tick "$(date +%s)"
    if [ "$render_needed" = 1 ]; then render; fi
  fi
done
