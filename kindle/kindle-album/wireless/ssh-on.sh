#!/bin/sh
# 开启 WiFi 无线控制：用 KOReader 自带的 dropbear 在 2222 端口提供 SSH，只允许公钥登录。
# 用法：sh ssh-on.sh         （文库入口调用，屏幕显示 IP，并设为相册启动时自动开启）
#       sh ssh-on.sh quiet   （相册启动时调用，不画屏）
set -u
mode=${1:-}
src=/mnt/us/kindle-album/wireless
koreader=/mnt/us/koreader
home=/var/local/kindle-album/ssh
pidfile=/tmp/kindle-album-ssh.pid
port=2222

note() {
  printf '%s %s\n' "$(date '+%F %T')" "$1" >> "$src/status.txt" 2>/dev/null || :
  [ "$mode" = quiet ] || /usr/sbin/eips 1 5 "$1                    " >/dev/null 2>&1 || :
}
fail() { note "WiFi control FAILED: $1"; exit 1; }

[ "$(id -u)" = 0 ] || fail "not root"
[ -f "$koreader/dropbear" ] || fail "KOReader dropbear missing"

mkdir -p "$home/settings/SSH" || fail "cannot create $home"
chmod 700 "$home" "$home/settings" "$home/settings/SSH"

# 公钥：USB 放入的 authorized_keys 优先，复制到 /var/local（ext 分区，权限可控）
keys="$home/settings/SSH/authorized_keys"
if [ -s "$src/authorized_keys" ]; then
  grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-)' "$src/authorized_keys" || fail "authorized_keys invalid"
  if ! cmp -s "$src/authorized_keys" "$keys"; then
    cp "$src/authorized_keys" "$keys.tmp" && chmod 600 "$keys.tmp" && mv "$keys.tmp" "$keys" || fail "cannot install key"
  fi
fi
[ -s "$keys" ] || fail "no public key (run install.sh on the Mac)"
chmod 600 "$keys"

# dropbear 缓存到 /var/local 运行：/mnt/us 在接 USB 时会被卸载，不能让常驻进程占着它。
# KOReader 的 dropbear 按 RPATH=$ORIGIN/libs 加载 libz.so.1，所以连同它一起缓存。
cache() {
  if ! cmp -s "$1" "$2"; then
    cp "$1" "$2.tmp" && chmod 755 "$2.tmp" && mv "$2.tmp" "$2" || fail "cannot cache $(basename "$1")"
  fi
}
mkdir -p "$home/libs" || fail "cannot create $home/libs"
cache "$koreader/dropbear" "$home/dropbear"
[ -f "$koreader/libs/libz.so.1" ] && cache "$koreader/libs/libz.so.1" "$home/libs/libz.so.1"

running() {
  pid=$(cat "$pidfile" 2>/dev/null) || return 1
  case "$pid" in ''|*[!0-9]*) return 1;; esac
  [ "$(readlink "/proc/$pid/exe" 2>/dev/null)" = "$home/dropbear" ]
}

# 防火墙开洞（先删同样的规则，避免重复）
for _ in 1 2 3 4 5; do
  iptables -D INPUT -p tcp --dport "$port" -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null || break
done
for _ in 1 2 3 4 5; do
  iptables -D OUTPUT -p tcp --sport "$port" -m conntrack --ctstate ESTABLISHED -j ACCEPT 2>/dev/null || break
done
iptables -I INPUT -p tcp --dport "$port" -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT || fail "iptables INPUT"
iptables -I OUTPUT -p tcp --sport "$port" -m conntrack --ctstate ESTABLISHED -j ACCEPT || fail "iptables OUTPUT"

if ! running; then
  rm -f "$pidfile"
  # cwd 必须是 $home：KOReader 版 dropbear 从相对路径 settings/SSH 读公钥和主机密钥
  # -R 首次连接时生成主机密钥；-s 禁止密码登录
  (cd "$home" && ./dropbear -R -s -p "$port" -P "$pidfile") || fail "dropbear did not start"
  sleep 1
  running || fail "dropbear exited"
fi

[ "$mode" = quiet ] || : > "$home/autostart"

ip=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{split($2,a,"/"); print a[1]; exit}')
[ -n "$ip" ] || ip=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
[ -n "$ip" ] || ip="no-wifi"
printf 'ip=%s\nport=%s\n' "$ip" "$port" > "$src/address.txt" 2>/dev/null || :
note "WiFi control ON  $ip:$port"
