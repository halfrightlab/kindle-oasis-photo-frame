#!/bin/sh
# Power/UI transitions only. Device actions are performed by album.sh.
power_init() {
  power_phase=active
  native_exit_seen=0
  native_lock_seen=0
  resume_deadline=0
  power_yield=0
  power_photo=0
  sleep_photo_drawn=0
  sleep_photo_fingerprint=
  sleep_photo_guard_until=0
  sleep_photo_repairs=0
  sleep_draw_after=0
  sleep_next_change=0
  # Powerd stays up about 90 seconds after a wake, then sleeps at least about 90
  # seconds, so 80 gives one change before each suspend and one on each wake.
  lock_interval=80
  power_advance=0
  power_rtc=0
  power_query_failures=0
  power_resume=0
  power_abort=0
}
power_event() {
  power_yield=0; power_photo=0; power_rtc=0
  case "$1" in
    *goingToScreenSaver*)
      if [ "$power_phase" != locked ]; then
        sleep_photo_drawn=0; sleep_photo_fingerprint=; sleep_photo_guard_until=0; sleep_photo_repairs=0
        sleep_draw_after=0; power_advance=0
      fi
      power_phase=locked; native_exit_seen=0; native_lock_seen=0; resume_deadline=0
      power_yield=1;;
    *readyToSuspend*)
      if [ "$power_phase" = locked ]; then
        power_rtc=1
        if [ "$sleep_photo_drawn" = 0 ]; then power_photo=1; fi
      fi;;
    *goingToPasswdDlg*)
      power_phase=unlocking; native_exit_seen=0; power_advance=0
      resume_deadline=$(($2+30)); power_yield=1;;
    *wakeupFromSuspend*)
      # Powerd also wakes by itself while locked, so this alone is not an unlock.
      # Stay locked and redraw; if the photo is due and no unlock event follows,
      # draw the next one. The alarm may fire up to 10 seconds early.
      # A photo drawn just before this event was read needs no second flash.
      if [ "$power_phase" = locked ] && [ "$2" -ge "$((sleep_next_change-lock_interval+15))" ]; then
        sleep_photo_drawn=0; sleep_photo_fingerprint=; sleep_photo_guard_until=0; sleep_photo_repairs=0
        sleep_draw_after=$(($2+5))
        if [ "$(($2+15))" -ge "$sleep_next_change" ]; then power_advance=1; fi
      fi;;
    *outOfScreenSaver*)
      if [ "$power_phase" != active ]; then
        power_phase=unlocking; power_advance=0
        if [ "$resume_deadline" = 0 ]; then resume_deadline=$(($2+30)); fi
      fi;;
    *exitingScreenSaver*)
      if [ "$power_phase" != active ]; then
        native_exit_seen=1; power_phase=unlocking; power_advance=0
        if [ "$resume_deadline" = 0 ]; then resume_deadline=$(($2+30)); fi
      fi;;
  esac
}
power_tick() {
  power_resume=0; power_abort=0
  case "$1" in
    active|screenSaver|readyToSuspend) power_query_failures=0;;
    *)
      power_query_failures=$((power_query_failures+1))
      # A failed read is not proof of either a lock or an app failure. Yield
      # input/UI before waiting for the native transition, without drawing.
      if [ "$power_phase" = active ]; then
        power_phase=unlocking; native_exit_seen=0
        power_yield=1; resume_deadline=$(($2+30))
      # A single query is killed by every suspend; only a run of failures counts.
      elif [ "$power_query_failures" -ge 5 ] && [ "$resume_deadline" != 0 ] && [ "$2" -ge "$resume_deadline" ]; then
        power_abort=1
      fi
      return;;
  esac
  if [ "$power_phase" = active ] && [ "$1" != active ]; then
    power_phase=locked; native_exit_seen=0; resume_deadline=0; power_yield=1; sleep_photo_drawn=0
    sleep_photo_fingerprint=; sleep_photo_guard_until=0; sleep_photo_repairs=0
    sleep_draw_after=0; power_advance=0
  fi
  if [ "$1" != active ]; then native_lock_seen=1; fi
  # An unlock that never completed: the device is still locked, so own the photo again.
  if [ "$power_phase" = unlocking ] && [ "$1" != active ] && [ "$native_exit_seen" = 0 ] &&
     [ "$resume_deadline" != 0 ] && [ "$2" -ge "$resume_deadline" ]; then
    power_phase=locked; resume_deadline=0; sleep_photo_drawn=0; sleep_draw_after=0
  fi
  if [ "$power_phase" = locked ] && [ "$native_lock_seen" = 0 ]; then return; fi
  if [ "$power_phase" = locked ] && [ "$1" != active ] && [ "$sleep_photo_drawn" = 1 ] && [ "$2" -ge "$sleep_next_change" ]; then
    sleep_photo_drawn=0; sleep_photo_fingerprint=; sleep_photo_guard_until=0; sleep_photo_repairs=0
    power_advance=1
  fi
  if [ "$power_phase" = locked ] && [ "$1" != active ] && [ "$sleep_photo_drawn" = 0 ] && [ "$2" -ge "$sleep_draw_after" ]; then
    power_photo=1
  fi
  if [ "$power_phase" != active ] && [ "$1" = active ]; then
    if [ "$resume_deadline" = 0 ]; then resume_deadline=$(($2+30)); fi
    power_phase=unlocking
    if [ "$native_exit_seen" = 1 ]; then power_resume=1
    elif [ "$2" -ge "$resume_deadline" ]; then power_abort=1
    fi
  fi
}
