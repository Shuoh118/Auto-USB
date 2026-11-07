#!/system/bin/sh
case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=$(pwd) ;;
esac

if [ -f /data/adb/autousb/run/daemon.pid ]; then
  P=$(cat /data/adb/autousb/run/daemon.pid 2>/dev/null)
  [ -n "$P" ] && kill -9 "$P" 2>/dev/null
fi

for RP in resetprop /data/adb/magisk/resetprop /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop; do
  command -v "$RP" >/dev/null 2>&1 || [ -x "$RP" ] || continue
  "$RP" -n ro.adb.secure 1 2>/dev/null
  break
done

rm -rf /data/adb/autousb
rm -rf /data/local/tmp/autousb*

exit 0
