#!/bin/sh
# 回放真机事件序列，验证 power-state.sh 的状态转换。运行：sh tests/test-power-state.sh
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../kindle/kindle-album/fullscreen-v2/app/power-state.sh"
fails=0
expect() { # 说明 变量名 期望值
  eval "got=\$$2"
  if [ "$got" = "$3" ]; then echo "ok   $1: $2=$3"; else echo "FAIL $1: $2=$got，期望 $3"; fails=$((fails+1)); fi
}
locked_with_photo() {
  power_init
  power_event "goingToScreenSaver 2" 1000
  power_tick screenSaver 1001
  sleep_photo_drawn=1; sleep_next_change=1121
  power_event "readyToSuspend 10" 1060
  expect "准备深睡时设闹钟" power_rtc 1
  power_tick unavailable 1120
}

# 2026-11-08 真机日志：后台唤醒后再次深睡，旧版在这里 abort=1
locked_with_photo
expect "第一次深睡" power_abort 0
power_tick screenSaver 4700
power_event "wakeupFromSuspend 3589" 4700
expect "后台唤醒" power_phase locked
expect "后台唤醒" power_advance 1
power_tick screenSaver 4701
expect "唤醒后先等系统画完" power_photo 0
power_tick screenSaver 4705
expect "5 秒后重画" power_photo 1
sleep_photo_drawn=1; power_photo=0; power_advance=0; sleep_next_change=4825
power_event "readyToSuspend 10" 4760
power_tick unavailable 4793
expect "再次深睡不退出" power_abort 0
expect "再次深睡" power_phase locked

# 锁屏期间未深睡：到时间就换下一张，一直轮转
power_tick screenSaver 4824
expect "未到时间" power_advance 0
for t in 4825 4905; do
  power_tick screenSaver $t
  expect "到时间换图 $t" power_advance 1
  expect "到时间换图 $t" power_photo 1
  sleep_photo_drawn=1; power_photo=0; power_advance=0; sleep_next_change=$((t+80))
done

# 闹钟提前 10 秒唤醒也算到时间；提前很多（系统自己醒）只重画不换图
locked_with_photo
sleep_next_change=4710
power_event "wakeupFromSuspend 60" 4700
expect "闹钟提前唤醒" power_advance 1
locked_with_photo
sleep_next_change=4750
power_event "wakeupFromSuspend 60" 4700
expect "系统提前唤醒" power_advance 0
expect "系统提前唤醒要重画" sleep_photo_drawn 0

# 刚换完图才读到唤醒事件：不再闪第二次
locked_with_photo
sleep_next_change=4780
power_event "wakeupFromSuspend 90" 4705
expect "刚画完不重画" sleep_photo_drawn 1
expect "刚画完不换图" power_advance 0

# 用户唤醒：解锁事件取消换图，回到同一张
locked_with_photo
power_event "wakeupFromSuspend 3589" 4700
power_event "outOfScreenSaver 1" 4701
expect "用户唤醒不换图" power_advance 0
power_event "exitingScreenSaver" 4702
power_tick active 4702
expect "用户解锁后恢复" power_resume 1

# 深睡中用户解锁（只有 wakeup 和 exiting 事件）
locked_with_photo
power_event "wakeupFromSuspend 100" 4700
power_event "exitingScreenSaver" 4703
power_tick active 4703
expect "直接解锁恢复" power_resume 1
expect "直接解锁不换图" power_advance 0

# 变成亮屏却一直没有退出屏保事件：仍在 30 秒后交还系统
locked_with_photo
power_event "wakeupFromSuspend 100" 4700
power_tick active 4701
expect "亮屏等待解锁事件" power_abort 0
power_tick active 4731
expect "超时交还系统" power_abort 1

# 解锁中途又回到屏保：恢复锁屏状态并重画
locked_with_photo
power_event "outOfScreenSaver 1" 4700
power_tick screenSaver 4701
expect "解锁宽限内" power_phase unlocking
power_tick screenSaver 4730
expect "解锁未完成" power_phase locked
expect "解锁未完成" power_photo 1

# 电源状态持续读不到才放弃；中间读到一次就重新计数
locked_with_photo
power_tick screenSaver 4699
power_event "outOfScreenSaver 1" 4700
for t in 4731 4732 4733 4734; do power_tick unavailable $t; done
expect "连续失败 4 次" power_abort 0
power_tick screenSaver 4735
power_tick unavailable 4736
expect "计数已清零" power_query_failures 1
expect "计数已清零" power_abort 0
power_init
power_event "goingToPasswdDlg" 1000
for t in 1031 1032 1033 1034 1035; do power_tick unavailable $t; done
expect "连续失败 5 次" power_abort 1

[ "$fails" = 0 ] && echo "全部通过" || { echo "$fails 项失败"; exit 1; }
