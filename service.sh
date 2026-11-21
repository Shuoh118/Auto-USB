#!/system/bin/sh
case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=$(pwd) ;;
esac

[ -f "$MODDIR/disable" ] && exit 0

. "$MODDIR/bin/autousb.sh"
cfg_load

[ "$ENABLED" = "1" ] || { log 1 "ENABLED=0, service exits"; exit 0; }

i=0
while [ $i -lt 120 ]; do
  [ "$(agetprop sys.boot_completed)" = "1" ] && break
  sleep 1
  i=$((i+1))
done
log 1 "boot_completed after ${i}s"

sleep 2

# 等开机的这段时间用户可能把模块关了，重新读一遍再干活
cfg_load
if ! module_enabled; then
  log 1 "module disabled during boot wait, exit"
  module_active_prop 0
  exit 0
fi

if [ "$LOCK_ENABLED" = "1" ]; then
  WANT=$(lock_target)
else
  WANT=$(resolve_target "$ON_CONNECT")
fi

if [ "$LOCK_ENABLED" = "1" ]; then
  CUR=$(current_functions)
  if [ -n "$CUR" ] && fns_equal "$CUR" "$WANT"; then
    log 1 "boot lock already satisfied ($CUR)"
  else
    log 1 "boot lock: ${CUR:-<none>} -> ${WANT:-<none>}"
    apply_adb "$ADB_ON_CONNECT"
    apply_profile "${WANT:-none}"
  fi
elif [ "$PERSIST" = "1" ] && [ -n "$ON_CONNECT" ] && [ "$ON_CONNECT" != "none" ]; then
  CUR=$(current_functions)
  # 之前只比对第一个功能，mtp 在但 adb 掉了也会被当成"已就绪"，导致开机后 adb 不通
  if [ -n "$CUR" ] && fns_equal "$CUR" "$WANT"; then
    log 1 "boot composition already ok ($CUR)"
  else
    log 1 "boot composition = ${CUR:-<none>}, aligning to $WANT"
    apply_adb "$ADB_ON_CONNECT"
    apply_profile "${WANT:-none}"
  fi
fi

if [ "$INSECURE_ADB" = "1" ]; then
  set_insecure_adb 1
fi

# adb_enabled 是开发者选项里那个开关。组合里带 adb（哪怕是 keep 带来的）就得打开，
# 否则 adbd 不会起来，锁屏插线自然拿不到 adb。
ADB_NEEDED=0
[ "$ADB_ON_CONNECT" = "1" ] && ADB_NEEDED=1
[ "$ADB_ON_DISCONNECT" = "1" ] && ADB_NEEDED=1
case ",$WANT," in *,adb,*) ADB_NEEDED=1 ;; esac
if [ "$ADB_NEEDED" = "1" ]; then
  asettings put global adb_enabled 1
  log 1 "adb_enabled -> 1"
fi

DAEMON_OK=1
if [ "$DAEMON" = "1" ]; then
  if daemon_start >/dev/null 2>&1; then
    log 1 "daemon launched pid=$(daemon_pid)"
  elif sleep 2 && daemon_start >/dev/null 2>&1; then
    log 1 "daemon launched on retry pid=$(daemon_pid)"
  else
    DAEMON_OK=0
    log 1 "daemon failed to start"
  fi
fi

if [ "$DAEMON_OK" = "1" ]; then
  module_active_prop 1
else
  module_active_prop 0
fi
exit 0
