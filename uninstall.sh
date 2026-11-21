#!/system/bin/sh

# 先停守护进程，避免它在我们删目录之后又写回状态文件
if [ -f /data/adb/autousb/run/daemon.pid ]; then
  P=$(cat /data/adb/autousb/run/daemon.pid 2>/dev/null)
  case "$P" in
    ''|*[!0-9]*) ;;
    *)
      if [ -r "/proc/$P/cmdline" ]; then
        tr '\0' ' ' < "/proc/$P/cmdline" 2>/dev/null | grep -q autousbd || P=""
      fi
      if [ -n "$P" ]; then
        kill "$P" 2>/dev/null
        i=0
        while [ $i -lt 30 ]; do
          kill -0 "$P" 2>/dev/null || break
          sleep 0.1; i=$((i+1))
        done
        kill -0 "$P" 2>/dev/null && kill -9 "$P" 2>/dev/null
      fi
      ;;
  esac
fi

# 还原安装前记录的系统值，别把用户的 USB 组合/ADB 开关留在模块状态
B=/data/adb/autousb/install-baseline
if [ -f "$B" ]; then
  PERSIST=$(sed -n 's/^PERSIST_USB=//p' "$B" 2>/dev/null | head -n 1)
  ADBEN=$(sed -n 's/^ADB_ENABLED=//p' "$B" 2>/dev/null | head -n 1)
  case "$PERSIST" in
    ''|null) ;;
    *) setprop persist.sys.usb.config "$PERSIST" 2>/dev/null ;;
  esac
  case "$ADBEN" in
    0|1) settings put global adb_enabled "$ADBEN" 2>/dev/null ;;
  esac
fi

for RP in resetprop /data/adb/magisk/resetprop /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop; do
  command -v "$RP" >/dev/null 2>&1 || [ -x "$RP" ] || continue
  "$RP" -n ro.adb.secure 1 2>/dev/null
  break
done

setprop sys.autousb.active 0 2>/dev/null

rm -rf /data/adb/autousb
rm -rf /data/local/tmp/autousb-ffs /data/local/tmp/autousb-install

exit 0
