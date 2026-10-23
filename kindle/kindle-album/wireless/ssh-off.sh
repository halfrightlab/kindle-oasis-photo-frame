#!/bin/sh
# 关闭 WiFi 无线控制，并取消相册启动时自动开启。
set -u
home=/var/local/kindle-album/ssh
pidfile=/tmp/kindle-album-ssh.pid
port=2222

rm -f "$home/autostart"
pid=$(cat "$pidfile" 2>/dev/null || :)
case "$pid" in
  ''|*[!0-9]*) :;;
  *) if [ "$(readlink "/proc/$pid/exe" 2>/dev/null)" = "$home/dropbear" ]; then kill -TERM "$pid" 2>/dev/null || :; fi;;
esac
rm -f "$pidfile"
for _ in 1 2 3 4 5; do
  iptables -D INPUT -p tcp --dport "$port" -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null || break
done
for _ in 1 2 3 4 5; do
  iptables -D OUTPUT -p tcp --sport "$port" -m conntrack --ctstate ESTABLISHED -j ACCEPT 2>/dev/null || break
done
printf '%s WiFi control OFF\n' "$(date '+%F %T')" >> /mnt/us/kindle-album/wireless/status.txt 2>/dev/null || :
[ "${1:-}" = quiet ] || /usr/sbin/eips 1 5 "WiFi control OFF                    " >/dev/null 2>&1 || :
