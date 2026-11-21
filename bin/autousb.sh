#!/system/bin/sh

# Auto USB 公共函数库
# 被 autousbctl / autousbd.sh / service.sh / post-fs-data.sh / action.sh / usbauth.sh source
# 只依赖 Android 自带的 toybox / mksh，不需要 busybox。

# WebUI 宿主给的 PATH 可能不完整（尤其 ksu.exec / mmrl.exec），先兜底
PATH=/system/bin:/system/xbin:/data/adb/ksu/bin:/data/adb/ap/bin:/data/adb/magisk:/sbin${PATH:+:$PATH}
export PATH

# 从 bin/ 或模块根调用都能定位，找不到才退回安装路径（方便在电脑上跑测试）
if [ -z "${MODDIR:-}" ]; then
  _d=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
  if [ -f "$_d/module.prop" ]; then
    MODDIR=$_d
  elif [ -f "$_d/../module.prop" ]; then
    MODDIR=$(cd "$_d/.." && pwd)
  else
    MODDIR=/data/adb/modules/autousb
  fi
fi
CONF=$MODDIR/config/autousb.conf
# AUTOUSB_STATE_DIR 只给本地测试用，设备上永远是 /data/adb/autousb
STATEDIR=${AUTOUSB_STATE_DIR:-/data/adb/autousb}
RUNDIR=$STATEDIR/run
AUTHDIR=$STATEDIR/auth
PIDFILE=$RUNDIR/daemon.pid
STATEFILE=$RUNDIR/last-state
LOGFILE=$STATEDIR/autousb.log

mkdir -p "$STATEDIR" "$RUNDIR" "$AUTHDIR" 2>/dev/null
chmod 0700 "$STATEDIR" "$RUNDIR" "$AUTHDIR" 2>/dev/null

# getprop/settings/svc 在精简系统里可能缺失，缺了返回空而不是让脚本退出
have() { command -v "$1" >/dev/null 2>&1; }

agetprop() { have getprop && getprop "$1" 2>/dev/null; }
asetprop() { have setprop && setprop "$1" "$2" 2>/dev/null; }
# settings / svc 是 binder 调用，系统卡住时会一直不返回，把 WebUI 的 state 拖死
asettings() {
  have settings || return 1
  if have timeout; then timeout 5 settings "$@" 2>/dev/null; else settings "$@" 2>/dev/null; fi
}
asvc() {
  have svc || return 1
  if have timeout; then timeout 2 svc "$@" 2>/dev/null; else svc "$@" 2>/dev/null; fi
}

# resetprop 在 KernelSU / APatch 下不一定进 PATH，按固定路径再找一遍
resetprop_bin() {
  for c in resetprop /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop /data/adb/magisk/resetprop; do
    if command -v "$c" >/dev/null 2>&1; then printf '%s' "$c"; return 0; fi
    if [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}
RP=${RP:-$(resetprop_bin 2>/dev/null)}

# ---------------------------------------------------------------- 配置

cfg_defaults() {
  ENABLED=1
  DAEMON=1
  ON_CONNECT=mtp
  ON_DISCONNECT=keep
  OFF_PROFILE=mtp
  PERSIST=1
  ADB_ON_CONNECT=keep
  ADB_ON_DISCONNECT=keep
  INSECURE_ADB=0
  VENDOR_MODE=auto
  POLL_INTERVAL=1
  DEBOUNCE=2
  LOG_LEVEL=1
  LOG_MAX_KB=256
  LOCK_ENABLED=0
  LOCK_PROFILE=mtp
  LOCK_REASSERT=5
}

# int_or VALUE DEFAULT MIN MAX
int_or() {
  _v=$1
  case "$_v" in ''|*[!0-9]*) _v=$2 ;; esac
  [ "$_v" -lt "$3" ] 2>/dev/null && _v=$3
  [ "$_v" -gt "$4" ] 2>/dev/null && _v=$4
  printf '%s' "$_v"
}

CONF_KEYS='ENABLED DAEMON PERSIST INSECURE_ADB LOG_LEVEL LOG_MAX_KB POLL_INTERVAL DEBOUNCE LOCK_REASSERT ON_CONNECT ON_DISCONNECT OFF_PROFILE ADB_ON_CONNECT ADB_ON_DISCONNECT VENDOR_MODE LOCK_ENABLED LOCK_PROFILE'

cfg_key_ok() {
  case " $CONF_KEYS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

cfg_load() {
  cfg_defaults
  [ -f "$CONF" ] || return 0
  # 一次 sed 清掉注释/CR/空白，再顺着读。原来每行要起 4 个外部进程，
  # 手机上单次 cfg_load 能烧掉几百毫秒，WebUI 的 state 会明显卡。
  _tmp=$RUNDIR/.cfg.$$
  if sed -e 's/\r$//' -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$CONF" > "$_tmp" 2>/dev/null; then
    while IFS='=' read -r k v; do
      # 手改配置可能写成 "KEY = value"，这里补一下（正常文件不会走这两个分支）
      case "$k" in *[[:space:]]*) k=$(printf '%s' "$k" | tr -d ' \t\r') ;; esac
      case "$v" in ' '*|*' '*) v=$(printf '%s' "$v" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//') ;; esac
      cfg_key_ok "$k" || continue
      # 配置值只允许字母数字下划线和逗号，挡掉 eval 注入
      case "$v" in *[!A-Za-z0-9_,]*) continue ;; esac
      eval "$k=\$v"
    done < "$_tmp"
  fi
  rm -f "$_tmp" 2>/dev/null
  cfg_sanitize
  return 0
}

# 配置文件被手改坏时回落到安全默认值，别让一个 abc 把模块静默关掉
cfg_sanitize() {
  case "$ENABLED" in 0|1) ;; *) ENABLED=1 ;; esac
  case "$DAEMON" in 0|1) ;; *) DAEMON=1 ;; esac
  case "$PERSIST" in 0|1) ;; *) PERSIST=1 ;; esac
  case "$INSECURE_ADB" in 0|1) ;; *) INSECURE_ADB=0 ;; esac
  case "$LOCK_ENABLED" in 0|1) ;; *) LOCK_ENABLED=0 ;; esac
  case "$ADB_ON_CONNECT" in 0|1|keep) ;; *) ADB_ON_CONNECT=keep ;; esac
  case "$ADB_ON_DISCONNECT" in 0|1|keep) ;; *) ADB_ON_DISCONNECT=keep ;; esac
  case "$ON_DISCONNECT" in keep|restore|none) ;; *) ON_DISCONNECT=keep ;; esac
  case "$VENDOR_MODE" in auto|force) ;; *) VENDOR_MODE=auto ;; esac
  case "$ON_CONNECT" in '') ON_CONNECT=mtp ;; esac
  case "$OFF_PROFILE" in '') OFF_PROFILE=mtp ;; esac
  case "$LOCK_PROFILE" in '') LOCK_PROFILE=mtp ;; esac
  profile_valid "$ON_CONNECT" || ON_CONNECT=mtp
  profile_valid "$OFF_PROFILE" || OFF_PROFILE=mtp
  profile_valid "$LOCK_PROFILE" || LOCK_PROFILE=mtp
  POLL_INTERVAL=$(int_or "$POLL_INTERVAL" 1 1 60)
  DEBOUNCE=$(int_or "$DEBOUNCE" 2 0 60)
  LOG_LEVEL=$(int_or "$LOG_LEVEL" 1 0 3)
  LOG_MAX_KB=$(int_or "$LOG_MAX_KB" 256 16 4096)
  LOCK_REASSERT=$(int_or "$LOCK_REASSERT" 5 1 120)
}

# 组合名合法性：只允许已知功能 token，逗号分隔
profile_valid() {
  case "$1" in ''|none) return 0 ;; esac
  case "$1" in *[!a-z,]*) return 1 ;; esac
  case "$1" in *,|,*) return 1 ;; esac
  oldIFS=$IFS; IFS=,
  for part in $1; do
    case "$part" in
      adb|mtp|ptp|rndis|midi|ncm|hid|uac1|uac2|mass_storage|accessory|audio_source|qxr) ;;
      *) IFS=$oldIFS; return 1 ;;
    esac
  done
  IFS=$oldIFS
  return 0
}

# cfg_set KEY VALUE...
cfg_set() {
  key=$1
  shift
  val=$*
  cfg_key_ok "$key" || return 2
  # 和 cfg_load 的白名单保持一致，避免写进去一个自己都不认的值
  case "$val" in *[!A-Za-z0-9_,]*) return 3 ;; esac
  tmp=$CONF.tmp.$$
  : > "$tmp" 2>/dev/null || return 1
  found=0
  if [ -f "$CONF" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        "$key"=*) printf '%s=%s\n' "$key" "$val" >> "$tmp"; found=1 ;;
        *) printf '%s\n' "$line" >> "$tmp" ;;
      esac
    done < "$CONF"
  fi
  [ "$found" = "1" ] || printf '%s=%s\n' "$key" "$val" >> "$tmp"
  chmod 0600 "$tmp" 2>/dev/null
  mv -f "$tmp" "$CONF" 2>/dev/null || { rm -f "$tmp"; return 1; }
  return 0
}

# ---------------------------------------------------------------- 日志

log() {
  lvl=${1:-2}; shift
  case "${LOG_LEVEL:-1}" in ''|*[!0-9]*) return 0 ;; esac
  [ "$LOG_LEVEL" -ge "$lvl" ] 2>/dev/null || return 0
  printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$LOGFILE" 2>/dev/null
  log_rotate
}

log_rotate() {
  [ -f "$LOGFILE" ] || return 0
  case "${LOG_MAX_KB:-256}" in ''|*[!0-9]*) return 0 ;; esac
  sz=$(wc -c < "$LOGFILE" 2>/dev/null | tr -d ' ')
  case "$sz" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$sz" -gt $(( LOG_MAX_KB * 1024 )) ] 2>/dev/null; then
    tail -c $(( LOG_MAX_KB * 512 )) "$LOGFILE" > "$LOGFILE.tmp" 2>/dev/null &&
      mv "$LOGFILE.tmp" "$LOGFILE"
  fi
}

# ---------------------------------------------------------------- USB 探测

UDC_ROOT=${UDC_ROOT:-/sys/class/udc}
GADGET_ROOT=${GADGET_ROOT:-/config/usb_gadget}

udc_list() {
  for d in "$UDC_ROOT"/*; do
    [ -d "$d" ] || continue
    b=$(basename "$d")
    [ "$b" = "dummy_udc" ] && continue
    echo "$b"
  done
}

usb_link_state() {
  for d in $(udc_list); do
    s=$(cat "$UDC_ROOT/$d/state" 2>/dev/null)
    case "$s" in
      configured) echo configured; return 0 ;;
      powered)    echo powered;    return 0 ;;
    esac
  done
  # 部分内核没有 UDC 目录，退化为电源节点
  for p in /sys/class/power_supply/usb/online \
           /sys/class/power_supply/usb/present \
           /sys/class/power_supply/main/online; do
    [ -r "$p" ] || continue
    [ "$(cat "$p" 2>/dev/null)" = "1" ] && { echo powered; return 0; }
  done
  echo "not attached"
  return 0
}

usb_connected() {
  case "$(usb_link_state)" in
    configured) return 0 ;;
    powered)    return 2 ;;
  esac
  return 1
}

usb_hosted() {
  [ "$(usb_link_state)" = "configured" ]
}

gadget_functions() {
  c=""
  for f in "$GADGET_ROOT"/*/configs/*/; do
    [ -d "$f" ] || continue
    c=$(basename "$f")
    break
  done
  [ -n "$c" ] || return 0
  out=""
  for e in "$GADGET_ROOT"/*/configs/"$c"/*; do
    [ -e "$e" ] || continue
    n=$(basename "$e")
    case "$n" in
      bMaxPacketSize0|MaxPower|bmAttributes) continue ;;
    esac
    n=${n#ffs.}
    case "$n" in
      mtp|ptp|rndis|midi|accessory|audio_source|ncm|adb|hid|uac1|uac2|mass_storage|qxr)
        if [ -z "$out" ]; then out=$n; else out="$out,$n"; fi ;;
    esac
  done
  printf '%s' "$out"
}

current_functions() {
  out=$(gadget_functions)
  if [ -n "$out" ]; then printf '%s' "$out"; return 0; fi
  asvc usb getFunctions | sed 's/^none$//'
}

# WebUI 用：绝不做 binder 调用，避免 state 被 svc 卡住（有的机型一卡就是 2 秒）
current_functions_fast() {
  out=$(gadget_functions)
  if [ -n "$out" ]; then printf '%s' "$out"; return 0; fi
  s=$(agetprop sys.usb.state)
  printf '%s' "$s" | sed 's/^none$//'
}

# ---------------------------------------------------------------- 应用组合

adb_switch() {
  case "$1" in
    1)
      asettings put global adb_enabled 1
      # 有些 ROM 改完 setting 不会主动拉起 adbd，补一刀
      pidof adbd >/dev/null 2>&1 || asetprop ctl.start adbd
      ;;
    0)
      asettings put global adb_enabled 0
      ;;
  esac
}

apply_profile() {
  prof=$1
  [ "$prof" = "none" ] && prof=""

  log 1 "apply profile: ${prof:-<empty>}"

  # 高通/小米的 HIDL 分支只看 vendor.usb.config
  if [ "$VENDOR_MODE" = "force" ] || [ -n "$(agetprop vendor.usb.config)" ]; then
    [ -n "$prof" ] && asetprop vendor.usb.config "$prof"
  fi

  if [ -n "$prof" ]; then
    asvc usb setFunctions "$prof"; rc=$?
  else
    asvc usb setFunctions; rc=$?
  fi

  if [ "$PERSIST" = "1" ]; then
    # 空串会被框架当成未设置，显式写 none
    asetprop persist.sys.usb.config "${prof:-none}"
  fi
  return $rc
}

apply_adb() {
  case "$1" in
    1|0) adb_switch "$1" ;;
  esac
}

split_functions() {
  IN=$1
  HAS_ADB=0
  DATA=""
  oldIFS=$IFS; IFS=,
  for part in $IN; do
    case "$part" in
      adb) HAS_ADB=1 ;;
      none) ;;
      '') ;;
      *) if [ -z "$DATA" ]; then DATA=$part; else DATA="$DATA,$part"; fi ;;
    esac
  done
  IFS=$oldIFS
}

resolve_target() {
  split_functions "$1"
  _out=$DATA
  # 第二个参数可以覆盖 adb 策略（断开/恢复时用 ADB_ON_DISCONNECT）
  _policy=${2:-${ADB_ON_CONNECT:-keep}}
  case "$_policy" in
    1) _adb=1 ;;
    0) _adb=0 ;;
    *) _adb=$HAS_ADB ;;
  esac
  [ "$_adb" = "1" ] && _out=${_out:+$_out,}adb
  printf '%s' "$_out"
}

# 去空、去 none、排序，用来比较两组组合是否等价（不依赖 paste）
norm() {
  printf '%s' "$1" | tr ',' '\n' | sed '/^[[:space:]]*$/d;/^none$/d' | sort | tr '\n' ',' | sed 's/,$//'
}

fns_equal() {
  [ "$(norm "$1")" = "$(norm "$2")" ]
}

lock_target() {
  if [ "${LOCK_ENABLED:-0}" = "1" ]; then
    resolve_target "${LOCK_PROFILE:-mtp}"
  else
    resolve_target "${ON_CONNECT:-mtp}"
  fi
}

enforce_lock() {
  [ "${LOCK_ENABLED:-0}" = "1" ] || return 1
  want=$(lock_target)
  cur=$(current_functions)
  # 读不到当前组合时不要瞎改，否则会每秒重置一次 USB 连接
  [ -n "$cur" ] || return 1
  fns_equal "$cur" "$want" && return 1
  log 1 "lock: ${cur:-<none>} -> ${want:-<none>}"
  apply_profile "${want:-none}"
  return 0
}

set_insecure_adb() {
  want=$1
  cur=$(agetprop ro.adb.secure)
  if [ "$want" = "1" ]; then
    [ "$cur" = "0" ] && return 0
    [ -n "$RP" ] || return 1
    "$RP" -n ro.adb.secure 0 2>/dev/null || asetprop ro.adb.secure 0
    log 1 "ro.adb.secure -> 0"
  else
    [ "$cur" = "1" ] && return 0
    [ -n "$RP" ] || return 1
    "$RP" -n ro.adb.secure 1 2>/dev/null || asetprop ro.adb.secure 1
    log 1 "ro.adb.secure -> 1"
  fi
}

module_active_prop() {
  asetprop sys.autousb.active "$1"
}

module_enabled() {
  [ "$ENABLED" = "1" ] || return 1
  [ -f "$MODDIR/disable" ] && return 1
  return 0
}

# ---------------------------------------------------------------- 守护进程

daemon_pid() {
  [ -f "$PIDFILE" ] || return 0
  p=$(cat "$PIDFILE" 2>/dev/null)
  case "$p" in ''|*[!0-9]*) return 0 ;; esac
  kill -0 "$p" 2>/dev/null || return 0
  # PID 可能被系统复用，确认还是自己的守护进程
  if [ -r "/proc/$p/cmdline" ]; then
    tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q autousbd || return 0
  fi
  printf '%s' "$p"
}

LOCKDIR=$RUNDIR/.daemon.lock

# 简单的目录锁：WebUI、service.sh、命令行同时启停时不会起两个守护进程
lock_acquire() {
  i=0
  while [ $i -lt 50 ]; do
    if mkdir "$LOCKDIR" 2>/dev/null; then
      echo $$ > "$LOCKDIR/pid" 2>/dev/null
      return 0
    fi
    lp=$(cat "$LOCKDIR/pid" 2>/dev/null)
    case "$lp" in
      ''|*[!0-9]*) rm -rf "$LOCKDIR" 2>/dev/null; continue ;;
    esac
    kill -0 "$lp" 2>/dev/null || { rm -rf "$LOCKDIR" 2>/dev/null; continue; }
    sleep 0.1
    i=$((i+1))
  done
  return 1
}

lock_release() {
  rm -rf "$LOCKDIR" 2>/dev/null
}

daemon_start() {
  module_enabled || { echo "module disabled"; return 1; }
  lock_acquire || { echo "busy"; return 1; }
  rc=0
  p=$(daemon_pid)
  if [ -n "$p" ]; then
    echo "already running (pid $p)"
  else
    rm -f "$PIDFILE"
    # KernelSU 的 service.sh 退出后可能带走整个进程组，优先用 setsid 脱离
    if command -v setsid >/dev/null 2>&1; then
      setsid sh "$MODDIR/bin/autousbd.sh" >/dev/null 2>&1 < /dev/null &
    elif command -v nohup >/dev/null 2>&1; then
      nohup sh "$MODDIR/bin/autousbd.sh" >/dev/null 2>&1 < /dev/null &
    else
      sh "$MODDIR/bin/autousbd.sh" >/dev/null 2>&1 < /dev/null &
    fi
    echo $! > "$PIDFILE"
    # setsid 可能 fork，$! 不一定是守护进程本身；守护进程起来后会自己写 $$，
    # 这里轮询等它把 pid 文件修正过来
    i=0
    p=""
    while [ $i -lt 25 ]; do
      p=$(daemon_pid)
      [ -n "$p" ] && break
      sleep 0.1
      i=$((i+1))
    done
    if [ -n "$p" ]; then
      echo "started (pid $p)"
    else
      rm -f "$PIDFILE"
      echo "failed to start"
      rc=1
    fi
  fi
  lock_release
  return $rc
}

daemon_stop() {
  lock_acquire || { echo "busy"; return 1; }
  p=$(daemon_pid)
  if [ -z "$p" ]; then
    rm -f "$PIDFILE"
    lock_release
    echo "not running"
    return 0
  fi
  kill "$p" 2>/dev/null
  i=0
  while [ $i -lt 30 ]; do
    kill -0 "$p" 2>/dev/null || break
    sleep 0.1; i=$((i+1))
  done
  kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null
  rm -f "$PIDFILE"
  lock_release
  echo "stopped"
}
