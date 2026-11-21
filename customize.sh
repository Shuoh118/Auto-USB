#!/system/bin/sh
command -v ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }

MODPATH="${MODPATH:-$(pwd)}"
MODID=autousb
OLD_MOD=/data/adb/modules/$MODID

if [ -n "${KSU:-}" ]; then
  ROOT_SOL=KernelSU
  ROOT_VER="${KSU_KERNEL_VER_CODE:-$KSU_VER_CODE}"
elif [ -n "${APATCH:-}" ]; then
  ROOT_SOL=APatch
  ROOT_VER="${APATCH_VER_CODE:-unknown}"
elif [ -n "${MAGISK_VER:-}" ] || [ -d /data/adb/magisk ]; then
  ROOT_SOL=Magisk
  ROOT_VER="${MAGISK_VER_CODE:-unknown}"
else
  ROOT_SOL=Unknown
  ROOT_VER=unknown
fi

ui_print "- Root manager : $ROOT_SOL ($ROOT_VER)"
ui_print "- Module path  : $MODPATH"

# 三家管理器已解包；recovery 才需要自己解
if [ ! -f "$MODPATH/bin/autousb.sh" ]; then
  ui_print "- Unpacking module files"
  if [ -n "${ZIPFILE:-}" ] && [ -f "$ZIPFILE" ]; then
    unzip -o "$ZIPFILE" -x 'META-INF/*' 'README.md' -d "$MODPATH" >/dev/null 2>&1
  else
    ui_print "! ZIPFILE not found, payload missing"
  fi
fi

# 升级时保留用户配置（写在解包之后、改权限之前）
if [ -f "$OLD_MOD/config/autousb.conf" ] && [ "$OLD_MOD" != "$MODPATH" ]; then
  mkdir -p "$MODPATH/config" 2>/dev/null
  if cp -f "$OLD_MOD/config/autousb.conf" "$MODPATH/config/autousb.conf" 2>/dev/null; then
    ui_print "- Config kept from previous install"
  fi
fi

ARCH=$(getprop ro.product.cpu.abi 2>/dev/null)
case "$ARCH" in
  arm64*|armv8*) ABI=arm64-v8a ;;
  x86_64*)       ABI=x86_64 ;;
  *)             ABI="" ;;
esac
ui_print "- Device ABI  : ${ARCH:-unknown} -> ${ABI:-none}"

PAYLOAD_APK="$MODPATH/payload/autousbmtp.apk"
SO="$MODPATH/payload/lib/libusbmanager_auth.so"
if [ -f "$PAYLOAD_APK" ] && [ -n "$ABI" ]; then
  mkdir -p "$MODPATH/payload/lib" 2>/dev/null
  rm -f "$SO"
  # 不用 unzip -j（部分 toybox/recovery 的 unzip 不认），先解到临时目录再搬
  TMP_LIB="$MODPATH/payload/.lib.$$"
  rm -rf "$TMP_LIB"; mkdir -p "$TMP_LIB" 2>/dev/null
  unzip -o "$PAYLOAD_APK" "lib/$ABI/libusbmanager_auth.so" -d "$TMP_LIB" >/dev/null 2>&1
  if [ -f "$TMP_LIB/lib/$ABI/libusbmanager_auth.so" ]; then
    mv -f "$TMP_LIB/lib/$ABI/libusbmanager_auth.so" "$SO" 2>/dev/null
  fi
  rm -rf "$TMP_LIB"
  if [ -f "$SO" ]; then
    ui_print "- Auth backend: native lib ready ($ABI)"
  else
    ui_print "- Auth backend: no .so for $ABI, auth backend unavailable"
  fi
else
  ui_print "- Auth backend: payload not bundled, auth backend unavailable"
fi

set_perm_recursive() {
  chown -R "$1:$2" "$3" 2>/dev/null
  find "$3" -type d -exec chmod 0755 {} \; 2>/dev/null
  find "$3" -type f -exec chmod 0644 {} \; 2>/dev/null
}

set_perm_recursive 0 0 "$MODPATH"

for f in "$MODPATH"/bin/*.sh "$MODPATH"/bin/autousbctl \
         "$MODPATH"/service.sh "$MODPATH"/post-fs-data.sh \
         "$MODPATH"/uninstall.sh "$MODPATH"/action.sh \
         "$MODPATH"/META-INF/com/google/android/update-binary; do
  [ -f "$f" ] && chmod 0755 "$f" 2>/dev/null
done
chmod 0644 "$MODPATH"/module.prop "$MODPATH"/README.md 2>/dev/null
chmod 0600 "$MODPATH"/config/autousb.conf 2>/dev/null
# set_perm_recursive 会把 .so 改成 0644，这里改回来
[ -f "$SO" ] && chmod 0755 "$SO" 2>/dev/null

mkdir -p /data/adb/autousb/auth /data/adb/autousb/run /data/adb/autousb/ffs 2>/dev/null
chmod 0700 /data/adb/autousb /data/adb/autousb/auth /data/adb/autousb/run /data/adb/autousb/ffs 2>/dev/null

# 记录安装前的系统状态，卸载时还原（只在第一次安装时记）
BASELINE=/data/adb/autousb/install-baseline
if [ ! -f "$BASELINE" ]; then
  {
    printf 'PERSIST_USB=%s\n' "$(getprop persist.sys.usb.config 2>/dev/null)"
    printf 'ADB_ENABLED=%s\n' "$(settings get global adb_enabled 2>/dev/null)"
  } > "$BASELINE" 2>/dev/null
  chmod 0600 "$BASELINE" 2>/dev/null
fi

# 覆盖安装时先停掉旧守护进程，否则旧进程会拿着被替换掉的脚本继续跑
for P in /data/adb/autousb/run/daemon.pid "$OLD_MOD/run/daemon.pid"; do
  [ -f "$P" ] || continue
  OLD=$(cat "$P" 2>/dev/null)
  case "$OLD" in
    ''|*[!0-9]*) ;;
    *)
      if [ -r "/proc/$OLD/cmdline" ]; then
        tr '\0' ' ' < "/proc/$OLD/cmdline" 2>/dev/null | grep -q autousbd || OLD=""
      fi
      [ -n "$OLD" ] && kill "$OLD" 2>/dev/null
      ;;
  esac
  rm -f "$P"
done

if [ ! -f "$MODPATH/webroot/index.html" ]; then
  ui_print "! webroot/index.html missing, WebUI will not open"
fi

ui_print "- Installed. Reboot to activate."
ui_print "- After boot: su -c autousbctl status"
