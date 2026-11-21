#!/system/bin/sh
case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=$(pwd) ;;
esac

[ -f "$MODDIR/disable" ] && exit 0

CONF=$MODDIR/config/autousb.conf

# 带默认值读取：配置项缺失时不会把功能静默关掉
conf_get() {
  _def=$2
  _v=""
  if [ -f "$CONF" ]; then
    _v=$(sed -n "s/^$1=//p" "$CONF" 2>/dev/null | head -n 1 | tr -d '\r' | sed 's/[[:space:]]*#.*$//;s/^[[:space:]]*//;s/[[:space:]]*$//')
  fi
  [ -n "$_v" ] || _v=$_def
  printf '%s' "$_v"
}

ENABLED=$(conf_get ENABLED 1)
[ "$ENABLED" = "0" ] && exit 0

INSECURE=$(conf_get INSECURE_ADB 0)
PERSIST=$(conf_get PERSIST 1)
VENDOR_MODE=$(conf_get VENDOR_MODE auto)

ADB_ON=$(conf_get ADB_ON_CONNECT keep)

LOCK_ENABLED=$(conf_get LOCK_ENABLED 0)
if [ "$LOCK_ENABLED" = "1" ]; then
  PROFILE=$(conf_get LOCK_PROFILE mtp)
else
  PROFILE=$(conf_get ON_CONNECT mtp)
fi

# 把 adb 拼进开机组合。不拼的话 adbd 根本不会启动，
# 插线后要等守护进程起来才有 adb，锁屏期间更是完全不通。
case "$PROFILE" in
  ''|none) ;;
  *adb*)
    # ADB_ON_CONNECT=0 时要把组合里已有的 adb 去掉，不然带 adb 的旧组合会原样写回去
    if [ "$ADB_ON" = "0" ]; then
      PROFILE=$(printf '%s' "$PROFILE" | sed 's/^adb,//;s/,adb//;s/^adb$//')
      [ -n "$PROFILE" ] || PROFILE=none
    fi
    ;;
  *)
    if [ "$ADB_ON" = "1" ]; then
      PROFILE="$PROFILE,adb"
    fi
    ;;
esac

RP=""
for c in resetprop /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop /data/adb/magisk/resetprop; do
  command -v "$c" >/dev/null 2>&1 && { RP=$c; break; }
  [ -x "$c" ] && { RP=$c; break; }
done

set_ro() {
  key=$1; val=$2
  [ -n "$RP" ] || return 1
  "$RP" -n "$key" "$val" 2>/dev/null && return 0
  "$RP" "$key" "$val" 2>/dev/null
}

if [ "$INSECURE" = "1" ]; then
  set_ro ro.adb.secure 0
  set_ro ro.debuggable 1
  set_ro service.adb.root 1
fi

if [ -n "$PROFILE" ] && [ "$PROFILE" != "none" ]; then
  if [ "$PERSIST" = "1" ]; then
    setprop persist.sys.usb.config "$PROFILE" 2>/dev/null
  fi
  case "$VENDOR_MODE" in
    force)
      setprop vendor.usb.config "$PROFILE" 2>/dev/null
      ;;
    auto)
      [ -n "$(getprop vendor.usb.config 2>/dev/null)" ] && \
        setprop vendor.usb.config "$PROFILE" 2>/dev/null
      ;;
  esac
fi

mkdir -p /data/adb/autousb/run /data/adb/autousb/auth 2>/dev/null
chmod 0700 /data/adb/autousb /data/adb/autousb/run /data/adb/autousb/auth 2>/dev/null
chown -R 0:0 /data/adb/autousb 2>/dev/null

exit 0
