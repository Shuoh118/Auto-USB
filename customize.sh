#!/system/bin/sh
command -v ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }

MODPATH="${MODPATH:-$(pwd)}"
MODID=autousb

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
  unzip -o "$ZIPFILE" -x 'META-INF/*' 'README.md' -d "$MODPATH" >/dev/null 2>&1
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
  unzip -o -j "$PAYLOAD_APK" "lib/$ABI/libusbmanager_auth.so" \
        -d "$MODPATH/payload/lib" >/dev/null 2>&1
  if [ -f "$SO" ]; then
    chmod 0755 "$SO"
    ui_print "- Auth backend: native lib ready ($ABI)"
  else
    ui_print "- Auth backend: no .so for $ABI, shell path only"
  fi
else
  ui_print "- Auth backend: shell path only"
fi

set_perm_recursive() {
  chown -R "$1:$2" "$3" 2>/dev/null
  find "$3" -type d -exec chmod 0755 {} \; 2>/dev/null
  find "$3" -type f -exec chmod 0644 {} \; 2>/dev/null
}

set_perm_recursive 0 0 "$MODPATH"

for f in "$MODPATH"/bin/*.sh "$MODPATH"/bin/autousbctl \
         "$MODPATH"/service.sh "$MODPATH"/post-fs-data.sh \
         "$MODPATH"/uninstall.sh "$MODPATH"/action.sh; do
  [ -f "$f" ] && chmod 0755 "$f" 2>/dev/null
done
chmod 0644 "$MODPATH"/module.prop "$MODPATH"/README.md 2>/dev/null
chmod 0600 "$MODPATH"/config/autousb.conf 2>/dev/null

mkdir -p /data/adb/autousb/auth /data/adb/autousb/run /data/adb/autousb/ffs 2>/dev/null
chmod 0700 /data/adb/autousb /data/adb/autousb/auth /data/adb/autousb/run /data/adb/autousb/ffs 2>/dev/null

for P in /data/adb/autousb/run/daemon.pid /data/adb/modules/$MODID/run/daemon.pid; do
  [ -f "$P" ] || continue
  OLD=$(cat "$P" 2>/dev/null)
  [ -n "$OLD" ] && kill "$OLD" 2>/dev/null
  rm -f "$P"
done

ui_print "- Installed. Reboot to activate."
ui_print "- After boot: su -c autousbctl status"
