#!/system/bin/sh

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
STATEDIR=/data/adb/autousb
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
asettings() { have settings && settings "$@" 2>/dev/null; }
asvc() { have svc && svc "$@" 2>/dev/null; }

ENABLED=1
DAEMON=1
ON_CONNECT=mtp
ON_DISCONNECT=keep
OFF_PROFILE=mtp
PERSIST=1
ADB_ON_CONNECT=keep
ADB_ON_DISCONNECT=keep
INSECURE_ADB=1
VENDOR_MODE=auto
POLL_INTERVAL=1
DEBOUNCE=2
LOG_LEVEL=1
LOG_MAX_KB=256
LOCK_ENABLED=0
LOCK_PROFILE=mtp

cfg_load() {
  [ -f "$CONF" ] || return 0
  while IFS='=' read -r k v; do
    case "$k" in ''|\#*) continue ;; esac
    k=$(printf '%s' "$k" | tr -d ' \t\r')
    v=$(printf '%s' "$v" | sed 's/[[:space:]]*#.*$//' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$k" in
      ENABLED|DAEMON|PERSIST|INSECURE_ADB|LOG_LEVEL|LOG_MAX_KB|POLL_INTERVAL|DEBOUNCE|\
      ON_CONNECT|ON_DISCONNECT|OFF_PROFILE|ADB_ON_CONNECT|ADB_ON_DISCONNECT|VENDOR_MODE|\
      LOCK_ENABLED|LOCK_PROFILE)
        eval "$k=\$v"
        ;;
    esac
  done < "$CONF"
}

cfg_set() {
  key=$1; val=$2
  [ -f "$CONF" ] || : > "$CONF"
  if grep -q "^$key=" "$CONF"; then
    sed -i "s|^$key=.*|$key=$val|" "$CONF"
  else
    printf '%s=%s\n' "$key" "$val" >> "$CONF"
  fi
  chmod 0600 "$CONF" 2>/dev/null
}

log() {
  lvl=${1:-2}; shift
  [ "${LOG_LEVEL:-1}" -ge "$lvl" ] 2>/dev/null || return 0
  printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$LOGFILE" 2>/dev/null
  log_rotate
}

log_rotate() {
  [ -f "$LOGFILE" ] || return 0
  sz=$(wc -c < "$LOGFILE" 2>/dev/null | tr -d ' ')
  [ -n "$sz" ] || return 0
  if [ "$sz" -gt $(( ${LOG_MAX_KB:-256} * 1024 )) ] 2>/dev/null; then
    tail -c $(( ${LOG_MAX_KB:-256} * 512 )) "$LOGFILE" > "$LOGFILE.tmp" 2>/dev/null &&
      mv "$LOGFILE.tmp" "$LOGFILE"
  fi
}

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

current_functions() {
  c=""
  for f in "$GADGET_ROOT"/*/configs/*/; do
    [ -d "$f" ] || continue
    c=$(basename "$f")
    break
  done
  if [ -n "$c" ]; then
    out=""
    for e in "$GADGET_ROOT"/*/configs/"$c"/*; do
      [ -e "$e" ] || continue
      n=$(basename "$e")
      case "$n" in
        bMaxPacketSize0|MaxPower|bmAttributes) continue ;;
      esac
      n=${n#ffs.}
      case "$n" in
        mtp|ptp|rndis|midi|accessory|audio_source|ncm|adb|hid|uac1|uac2|mass_storage)
          if [ -z "$out" ]; then out=$n; else out="$out,$n"; fi ;;
      esac
    done
    [ -n "$out" ] && { echo "$out"; return 0; }
  fi
  asvc usb getFunctions | sed 's/^none$//'
}

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
  [ -n "$prof" ] || return 1
  [ "$prof" = "none" ] && prof=""

  log 1 "apply profile: ${prof:-<empty>}"

  # 高通/小米的 HIDL 分支只看 vendor.usb.config
  if [ "$VENDOR_MODE" = "force" ] || [ -n "$(agetprop vendor.usb.config)" ]; then
    [ -n "$prof" ] && asetprop vendor.usb.config "$prof"
  fi

  if [ -n "$prof" ]; then
    asvc usb setFunctions "$prof"
  else
    asvc usb setFunctions
  fi

  if [ "$PERSIST" = "1" ]; then
    # 空串会被框架当成未设置，显式写 none
    asetprop persist.sys.usb.config "${prof:-none}"
  fi
  return 0
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
  case "${ADB_ON_CONNECT:-keep}" in
    1) _adb=1 ;;
    0) _adb=0 ;;
    *) _adb=$HAS_ADB ;;
  esac
  [ "$_adb" = "1" ] && _out=${_out:+$_out,}adb
  printf '%s' "$_out"
}

norm() {
  printf '%s' "$1" | tr ',' '\n' | sed '/^[[:space:]]*$/d;/^none$/d' | sort | paste -sd, -
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
  if [ "$(norm "$cur")" = "$(norm "$want")" ]; then
    return 1
  fi
  log 1 "lock: ${cur:-<none>} -> ${want:-<none>}"
  apply_profile "${want:-none}"
  return 0
}

set_insecure_adb() {
  want=$1
  cur=$(agetprop ro.adb.secure)
  if [ "$want" = "1" ]; then
    [ "$cur" = "0" ] && return 0
    resetprop -n ro.adb.secure 0 2>/dev/null || asetprop ro.adb.secure 0
    log 1 "ro.adb.secure -> 0"
  else
    [ "$cur" = "1" ] && return 0
    resetprop -n ro.adb.secure 1 2>/dev/null || asetprop ro.adb.secure 1
    log 1 "ro.adb.secure -> 1"
  fi
}

module_active_prop() {
  asetprop sys.autousb.active "$1"
}

daemon_pid() {
  [ -f "$PIDFILE" ] || { echo ""; return; }
  p=$(cat "$PIDFILE" 2>/dev/null)
  case "$p" in ''|*[!0-9]*) echo ""; return ;; esac
  kill -0 "$p" 2>/dev/null || { echo ""; return; }
  echo "$p"
}

daemon_start() {
  [ "$ENABLED" = "1" ] || { echo "module disabled"; return 1; }
  p=$(daemon_pid)
  if [ -n "$p" ]; then echo "already running (pid $p)"; return 0; fi
  rm -f "$PIDFILE"
  nohup sh "$MODDIR/bin/autousbd.sh" >/dev/null 2>&1 &
  echo $! > "$PIDFILE"
  echo "started (pid $(cat "$PIDFILE"))"
}

daemon_stop() {
  p=$(daemon_pid)
  if [ -z "$p" ]; then rm -f "$PIDFILE"; echo "not running"; return 0; fi
  kill "$p" 2>/dev/null
  i=0
  while [ $i -lt 30 ]; do
    kill -0 "$p" 2>/dev/null || break
    sleep 0.1; i=$((i+1))
  done
  kill -9 "$p" 2>/dev/null
  rm -f "$PIDFILE"
  echo "stopped"
}
