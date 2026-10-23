#!/bin/sh
set -u
runtime=/tmp/kindle-album-session
base=/mnt/us/kindle-album/fullscreen-v2/data
log=/mnt/us/kindle-album/fullscreen-v2/data/session.log
expected_pid=$1
expected_start=$(cat "$runtime/app-start" 2>/dev/null || :)
app_owned() {
  [ -n "$expected_start" ] &&
    [ "$(awk '{print $22}' "/proc/$expected_pid/stat" 2>/dev/null)" = "$expected_start" ]
}
stop_app() {
  app_owned || return 0
  kill -TERM "$expected_pid" 2>/dev/null || :
  stop_wait=0
  while app_owned && [ "$stop_wait" -lt 3 ]; do
    sleep 1; stop_wait=$((stop_wait+1))
  done
  if app_owned; then kill -KILL "$expected_pid" 2>/dev/null || :; fi
}
last_seen=$(date +%s)
last_checked=$last_seen
resume_grace=0
while [ -f "$runtime/pid" ] && [ "$(cat "$runtime/pid")" = "$expected_pid" ]; do
  heartbeat=$(cat "$runtime/heartbeat" 2>/dev/null || :)
  case "$heartbeat" in ''|*[!0-9]*) :;; *) last_seen=$heartbeat;; esac
  now=$(date +%s)
  phase=$(cat "$runtime/power-phase" 2>/dev/null || printf active)
  if [ ! -r "$base/project-id" ] ||
     [ "$(cat "$base/project-id" 2>/dev/null)" != kindle-oasis-album-20261022 ]; then
    # This check is independent of event delivery and works with a stuck app.
    printf 'usb\n' > "$runtime/power-phase"
    stop_app
    sh "$runtime/cleanup.sh"
    exit 0
  fi
  if kill -0 "$expected_pid" 2>/dev/null && [ "$phase" != active ]; then
    native_state=$(timeout 3 lipc-get-prop com.lab126.powerd state 2>/dev/null || printf unavailable)
    now=$(date +%s)
    # A grace can already have started during the LIPC gap before suspend.
    # After a long scheduling/query gap, it cannot be reused as a wake deadline.
    if [ "$((now-last_checked))" -gt 15 ]; then
      resume_grace=0
      printf 'watchdog_resume_gap_seconds=%s time=%s\n' "$((now-last_checked))" "$now" >> "$log" || :
    fi
    last_checked=$now
    case "$native_state" in
      screenSaver|readyToSuspend)
        resume_grace=0
        sleep 3
        continue;;
      *)
        # A suspended query may resume with active or a transient LIPC error.
        # Both need a fresh, bounded grace before judging the old heartbeat.
        if [ "$resume_grace" = 0 ]; then resume_grace=$((now+15)); fi
        if [ "$now" -lt "$resume_grace" ]; then sleep 3; continue; fi;;
    esac
  else
    resume_grace=0
    last_checked=$now
  fi
  # The app may have refreshed its heartbeat while the query was blocked.
  heartbeat=$(cat "$runtime/heartbeat" 2>/dev/null || :)
  case "$heartbeat" in ''|*[!0-9]*) :;; *) last_seen=$heartbeat;; esac
  if ! kill -0 "$expected_pid" 2>/dev/null || [ "$((now-last_seen))" -gt 15 ]; then
    printf 'watchdog_recovery=yes heartbeat_age=%s phase=%s time=%s\n' "$((now-last_seen))" "$phase" "$now" >> "$log" || :
    stop_app
    sh "$runtime/cleanup.sh"
    exit 0
  fi
  sleep 3
done
