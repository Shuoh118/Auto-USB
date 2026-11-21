#!/system/bin/sh
case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=$(pwd) ;;
esac

. "$MODDIR/bin/autousb.sh"
cfg_load

echo "autousb $(grep -m1 '^version=' "$MODDIR/module.prop" | cut -d= -f2)"
echo "--------------------------------"
if [ -f "$MODDIR/disable" ]; then
  echo "enabled     : no (disable flag)"
elif [ "$ENABLED" = "1" ]; then
  echo "enabled     : yes"
else
  echo "enabled     : no (ENABLED=0)"
fi
echo "usb state   : $(usb_link_state)"
echo "functions   : $(current_functions)"
p=$(daemon_pid)
[ -n "$p" ] && echo "daemon      : running ($p)" || echo "daemon      : stopped"
if [ "$LOCK_ENABLED" = "1" ]; then
  echo "mode        : LOCK -> $(lock_target)"
else
  echo "mode        : AUTO -> ${ON_CONNECT:-none}"
fi
echo "--------------------------------"

if ! module_enabled; then
  echo "module disabled — 先 su -c autousbctl on 启用"
  exit 0
fi

TARGET=$(lock_target)

if [ "$USBMTP_ACTION_NOAPPLY" = "1" ]; then
  echo "target      : ${TARGET:-<none>} (not applied)"
else
  apply_adb "$ADB_ON_CONNECT"
  apply_profile "${TARGET:-none}"
  sleep 1
  echo "applied     -> ${TARGET:-<none>}"
  echo "now         : $(current_functions)"
fi

echo "--------------------------------"
echo "锁定切换：su -c autousbctl lock on ptp"
echo "详细状态：su -c autousbctl status"
exit 0
