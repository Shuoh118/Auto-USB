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
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  sleep 1
  i=$((i+1))
done
log 1 "boot_completed after ${i}s"

sleep 2

if [ "$LOCK_ENABLED" = "1" ]; then
  WANT=$(lock_target)
  CUR=$(current_functions)
  if [ "$(norm "$CUR")" = "$(norm "$WANT")" ]; then
    log 1 "boot lock already satisfied ($CUR)"
  else
    log 1 "boot lock: ${CUR:-<none>} -> ${WANT:-<none>}"
    apply_adb "$ADB_ON_CONNECT"
    apply_profile "${WANT:-none}"
  fi
elif [ "$PERSIST" = "1" ] && [ -n "$ON_CONNECT" ] && [ "$ON_CONNECT" != "none" ]; then
  CUR=$(current_functions)
  case ",$CUR," in
    *",${ON_CONNECT%%,*},"*) log 1 "boot composition already ok ($CUR)" ;;
    *)
      log 1 "boot composition = ${CUR:-<none>}, aligning to $ON_CONNECT"
      apply_profile "$ON_CONNECT"
      ;;
  esac
fi

if [ "$INSECURE_ADB" = "1" ]; then
  set_insecure_adb 1
fi

# adb_enabled 是开发者选项里那个开关。不打开的话即使 USB 组合里带 adb，
# adbd 也不会起来 —— 锁屏插线自然拿不到 adb。
if [ "$ADB_ON_CONNECT" = "1" ] || [ "$ADB_ON_DISCONNECT" = "1" ]; then
  asettings put global adb_enabled 1
  log 1 "adb_enabled -> 1"
fi

if [ "$DAEMON" = "1" ]; then
  daemon_start >/dev/null 2>&1
  log 1 "daemon launched pid=$(cat "$PIDFILE" 2>/dev/null)"
fi

module_active_prop 1
exit 0
