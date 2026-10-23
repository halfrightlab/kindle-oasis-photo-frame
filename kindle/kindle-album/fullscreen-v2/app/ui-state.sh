#!/bin/sh
# Pure UI state: no device access, files, processes, or network calls.
ui_init() {
  controls_visible=0
  controls_until=0
  slide_deadline=$(($1+interval))
  wants_exit=0
  render_needed=1
  persist_interval=0
  persist_mode=0
}
ui_tap() {
  tap_x=$1; tap_y=$2; tap_now=$3
  # An expired bar must behave as hidden even before the next clock tick.
  if [ "$controls_visible" = 1 ] && [ "$tap_now" -ge "$controls_until" ]; then controls_visible=0; fi
  if [ "$controls_visible" = 0 ]; then
    controls_visible=1
    controls_until=$((tap_now+5))
    render_needed=1
    return
  fi
  controls_until=$((tap_now+5))
  if [ "$tap_y" -lt 1504 ] || [ "$tap_y" -gt 1648 ] || [ "$tap_x" -lt 32 ] || [ "$tap_x" -ge 1232 ]; then return; fi
  case "$(((tap_x-32)/240))" in
    0) index=$(((index+count-2)%count+1)); slide_deadline=$((tap_now+interval));;
    1)
      case "$interval" in 10) interval=30;; 30) interval=60;; 60) interval=300;; 300) interval=10;; esac
      persist_interval=1; slide_deadline=$((tap_now+interval));;
    2) index=$((index%count+1)); slide_deadline=$((tap_now+interval));;
    3)
      case "$fit_mode" in crop) fit_mode=contain;; *) fit_mode=crop;; esac
      persist_mode=1;;
    4) wants_exit=1;;
  esac
  render_needed=1
}
ui_tick() {
  tick_now=$1
  if [ "$controls_visible" = 1 ] && [ "$tick_now" -ge "$controls_until" ]; then
    controls_visible=0; render_needed=1
  fi
  if [ "$tick_now" -ge "$slide_deadline" ]; then
    index=$((index%count+1))
    slide_deadline=$((tick_now+interval))
    render_needed=1
  fi
}
