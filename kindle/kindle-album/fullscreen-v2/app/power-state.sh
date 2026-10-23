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
  power_resume=0
  power_abort=0
}
power_event() {
  power_yield=0; power_photo=0
  case "$1" in
    *goingToScreenSaver*)
      if [ "$power_phase" != locked ]; then
        sleep_photo_drawn=0; sleep_photo_fingerprint=; sleep_photo_guard_until=0; sleep_photo_repairs=0
      fi
      power_phase=locked; native_exit_seen=0; native_lock_seen=0; resume_deadline=0
      power_yield=1;;
    *readyToSuspend*)
      if [ "$power_phase" = locked ] && [ "$sleep_photo_drawn" = 0 ]; then power_photo=1; fi;;
    *goingToPasswdDlg*)
      power_phase=unlocking; native_exit_seen=0
      resume_deadline=$(($2+30)); power_yield=1;;
    *wakeupFromSuspend*|*outOfScreenSaver*)
      if [ "$power_phase" != active ]; then
        power_phase=unlocking
        if [ "$resume_deadline" = 0 ]; then resume_deadline=$(($2+30)); fi
      fi;;
    *exitingScreenSaver*)
      if [ "$power_phase" != active ]; then
        native_exit_seen=1; power_phase=unlocking
        if [ "$resume_deadline" = 0 ]; then resume_deadline=$(($2+30)); fi
      fi;;
  esac
}
power_tick() {
  power_resume=0; power_abort=0
  case "$1" in
    active|screenSaver|readyToSuspend) :;;
    *)
      # A failed read is not proof of either a lock or an app failure. Yield
      # input/UI before waiting for the native transition, without drawing.
      if [ "$power_phase" = active ]; then
        power_phase=unlocking; native_exit_seen=0
        power_yield=1; resume_deadline=$(($2+30))
      elif [ "$resume_deadline" != 0 ] && [ "$2" -ge "$resume_deadline" ]; then
        power_abort=1
      fi
      return;;
  esac
  if [ "$power_phase" = active ] && [ "$1" != active ]; then
    power_phase=locked; native_exit_seen=0; resume_deadline=0; power_yield=1; sleep_photo_drawn=0
    sleep_photo_fingerprint=; sleep_photo_guard_until=0; sleep_photo_repairs=0
  fi
  if [ "$1" != active ]; then native_lock_seen=1; fi
  if [ "$power_phase" = locked ] && [ "$native_lock_seen" = 0 ]; then return; fi
  if [ "$power_phase" = locked ] && [ "$1" != active ] && [ "$sleep_photo_drawn" = 0 ]; then
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
