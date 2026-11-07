#!/system/bin/sh
case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=$(pwd) ;;
esac

. "$MODDIR/bin/autousb.sh"
cfg_load

echo "autousb $(grep -m1 '^version=' "$MODDIR/module.prop" | cut -d= -f2)"
echo "--------------------------------"
echo "usb state   : $(usb_link_state)"
echo "functions   : $(current_functions)"
p=$(daemon_pid)
[ -n "$p" ] && echo "daemon      : running ($p)" || echo "daemon      : stopped"
if [ "$LOCK_ENABLED" = "1" ]; then
  echo "mode        : LOCK -> ${LOCK_PROFILE:-none}"
else
  echo "mode        : AUTO -> ${ON_CONNECT:-none}"
fi
echo "--------------------------------"

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
