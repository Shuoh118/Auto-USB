#!/system/bin/sh

SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
[ -f "$SELF/../bin/autousb.sh" ] || SELF=/data/adb/modules/autousb/bin
. "$SELF/../bin/autousb.sh"
cfg_load

MODDIR=${MODDIR:-/data/adb/modules/autousb}
APK=$MODDIR/payload/autousbmtp.apk
LIB=$MODDIR/payload/lib/libusbmanager_auth.so
ROOT=$STATEDIR/ffs
HOSTS=$ROOT/hosts
RUN=$ROOT/session
MOUNT_STAGE=/data/local/tmp/autousb-ffs
pick_daemon_class() {
  for c in io.github.shuoh118.autousbmtp.auth.UsbAuthDaemon \
           com.tiger.usbmanager.auth.UsbAuthDaemon; do
    if unzip -p "$APK" 'classes*.dex' 2>/dev/null | grep -qa "$(echo "$c" | tr . /)"; then
      echo "$c"; return 0
    fi
  done
  return 1
}
DAEMON_CLASS=${DAEMON_CLASS:-$(pick_daemon_class 2>/dev/null || echo io.github.shuoh118.autousbmtp.auth.UsbAuthDaemon)}

mkdir -p "$ROOT" "$HOSTS" 2>/dev/null
chmod 0700 "$ROOT" "$HOSTS" 2>/dev/null

have_payload() {
  [ -f "$APK" ] && [ -f "$LIB" ] || return 1
  return 0
}

find_conf() {
  for c in /odm/etc/usb_compositions.conf /product/etc/usb_compositions.conf /vendor/etc/usb_compositions.conf; do
    [ -r "$c" ] || continue
    grep -q '^qxr,adb[[:space:]]' "$c" 2>/dev/null || continue
    echo "$c"
    return 0
  done
  return 1
}

ffs_mount() {
  M=$1
  mkdir -p "$M" 2>/dev/null
  mountpoint -q "$M" && return 0
  mount -t functionfs usb_auth "$M" 2>/dev/null
}

daemon_start() {
  MNT=$1; PAIR=$2; LOG=$3; RESULT=$4
  rm -f "$RESULT" "$RESULT.tmp"
  CLASSPATH="$APK" app_process /system/bin "$DAEMON_CLASS" \
      "$LIB" "$MNT" "$HOSTS" "$PAIR" "$RESULT" "${PROFILE:-none}" > "$LOG" 2>&1 &
  DAEMON=$!
  i=0
  while [ $i -lt 30 ]; do
    grep -q '^READY ' "$LOG" 2>/dev/null && return 0
    sleep 0.1; i=$((i+1))
  done
  return 1
}

generic_capable() {
  [ -d /config/usb_gadget ] || return 1
  grep -qw functionfs /proc/filesystems || return 1
  [ -n "$(ls /sys/class/udc 2>/dev/null)" ] || return 1
  return 0
}

generic_prepare() {
  G=/config/usb_gadget/g1
  [ -d "$G/functions" ] && [ -d "$G/configs" ] || return 1
  C=$(find "$G/configs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)
  [ -n "$C" ] || return 1
  UDC=$(cat "$G/UDC" 2>/dev/null)
  [ -n "$UDC" ] || return 1
  [ -d "/sys/class/udc/$UDC" ] || return 1

  F=/dev/usb-ffs/usb_auth
  FN=$G/functions/ffs.usb_auth
  LINK=$C/autousb_auth
  [ ! -e "$FN" ] && [ ! -L "$LINK" ] || return 1

  ffs_mount "$F" || return 1
  daemon_start "$F" "$MODE" "$RUN/daemon.log" "$RUN/auth-result" || return 1
  echo "$DAEMON" > "$RUN/daemon.pid"
  echo "$UDC" > "$RUN/generic.udc"
  echo "$LINK" > "$RUN/generic.link"
  touch "$RUN/generic"

  echo '' > "$G/UDC" 2>/dev/null
  mkdir "$FN" 2>/dev/null
  ln -s "$FN" "$LINK" 2>/dev/null
  echo "$UDC" > "$G/UDC" 2>/dev/null

  i=0
  while [ $i -lt 30 ]; do
    [ "$(cat "$G/UDC" 2>/dev/null)" = "$UDC" ] && return 0
    sleep 0.1; i=$((i+1))
  done
  return 1
}

qxr_prepare() {
  CONF=$1
  QXR=/dev/usb-ffs/qxr
  [ -e "$QXR/ep0" ] && [ ! -e "$QXR/ep1" ] || return 1

  rm -rf "$MOUNT_STAGE"
  mkdir -p "$MOUNT_STAGE" 2>/dev/null || return 1
  chmod 0700 "$MOUNT_STAGE"
  cp "$CONF" "$MOUNT_STAGE/patched.conf" || return 1
  echo 'mtp,qxr,adb  0x05C6  0xD003' >> "$MOUNT_STAGE/patched.conf"
  chmod 0600 "$MOUNT_STAGE/patched.conf"
  chcon u:object_r:vendor_configs_file:s0 "$MOUNT_STAGE/patched.conf" 2>/dev/null
  mount --bind "$MOUNT_STAGE/patched.conf" "$CONF" || return 1

  i=0
  while [ $i -lt 80 ]; do
    [ -e /dev/usb-ffs/mtp/ep1 ] && break
    sleep 0.1; i=$((i+1))
  done
  [ -e /dev/usb-ffs/mtp/ep1 ] || return 1

  daemon_start "$QXR" "$MODE" "$RUN/daemon.log" "$RUN/auth-result" || return 1
  echo "$DAEMON" > "$RUN/daemon.pid"

  OLD_HAL=$(pidof android.hardware.usb.gadget@1.2-service-qti 2>/dev/null)
  setprop ctl.restart vendor.usbgadget-hal-1-2 2>/dev/null
  HAL=''
  i=0
  while [ $i -lt 100 ]; do
    HAL=$(pidof android.hardware.usb.gadget@1.2-service-qti 2>/dev/null)
    [ "$(getprop init.svc.vendor.usbgadget-hal-1-2)" = running ] &&
      [ -n "$HAL" ] && [ "$HAL" != "$OLD_HAL" ] && break
    sleep 0.1; i=$((i+1))
  done
  [ -n "$HAL" ] && [ "$HAL" != "$OLD_HAL" ] || return 1

  rows=0
  [ -z "$HAL" ] || rows=$(grep -c '^mtp,qxr,adb[[:space:]]' "/proc/$HAL/root$CONF" 2>/dev/null || echo 0)
  [ "$rows" -gt 0 ] || return 1

  settings put global adb_enabled 1 2>/dev/null
  setprop vendor.usb.config mtp,qxr,adb 2>/dev/null
  svc usb setFunctions 2>/dev/null

  i=0
  while [ $i -lt 100 ]; do
    PID=$(cat /config/usb_gadget/g1/idProduct 2>/dev/null)
    LINKS=$(ls -l /config/usb_gadget/g1/configs/b.1 2>/dev/null)
    if [ "$PID" = 0xd003 ] &&
       echo "$LINKS" | grep -q ffs.mtp &&
       echo "$LINKS" | grep -q ffs.qxr &&
       echo "$LINKS" | grep -q ffs.adb; then
      return 0
    fi
    sleep 0.1; i=$((i+1))
  done
  return 1
}

save_state() {
  mkdir "$RUN" 2>/dev/null || return 1
  getprop vendor.usb.config > "$RUN/vendor-config" 2>/dev/null
  getprop persist.vendor.usb.config.extra > "$RUN/extra" 2>/dev/null
  LINKS=$(ls -l /config/usb_gadget/g1/configs/b.1 2>/dev/null)
  echo "$LINKS" | grep -q ffs.adb && echo 1 > "$RUN/adb" || echo 0 > "$RUN/adb"
  COMP=''
  for n in mtp ptp rndis midi accessory audio_source ncm qxr adb; do
    echo "$LINKS" | grep -q "\\.$n" || continue
    COMP=${COMP:+$COMP,}$n
  done
  echo "${COMP:-none}" > "$RUN/functions"
}

do_restore() {
  [ -d "$RUN" ] || return 0
  mkdir "$RUN/restoring" 2>/dev/null || true
  rm -f "$RUN/watchdog.armed"

  [ ! -f "$RUN/daemon.log" ] || cp "$RUN/daemon.log" "$ROOT/last-daemon.log" 2>/dev/null
  [ ! -f "$RUN/daemon.pid" ] || kill "$(cat "$RUN/daemon.pid" 2>/dev/null)" 2>/dev/null
  sleep 0.3

  if [ -f "$RUN/generic" ]; then
    G=/config/usb_gadget/g1
    UDC=$(cat "$RUN/generic.udc" 2>/dev/null)
    LINK=$(cat "$RUN/generic.link" 2>/dev/null)
    echo '' > "$G/UDC" 2>/dev/null
    rm -f "$LINK" 2>/dev/null
    rmdir "$G/functions/ffs.usb_auth" 2>/dev/null
    [ -n "$UDC" ] && echo "$UDC" > "$G/UDC" 2>/dev/null
    umount /dev/usb-ffs/usb_auth 2>/dev/null
    rmdir /dev/usb-ffs/usb_auth 2>/dev/null
    rm -rf "$RUN"
    return 0
  fi

  CONF=$(find_conf)
  SAVED_ADB=$(cat "$RUN/adb" 2>/dev/null)
  SAVED_FN=$(cat "$RUN/functions" 2>/dev/null)
  setprop persist.vendor.usb.config.extra "$(cat "$RUN/extra" 2>/dev/null)" 2>/dev/null
  setprop vendor.usb.config none 2>/dev/null
  svc usb setFunctions >/dev/null 2>&1

  i=0
  while [ $i -lt 30 ]; do
    LINKS=$(ls -l /config/usb_gadget/g1/configs/b.1 2>/dev/null)
    echo "$LINKS" | grep -q ffs.qxr || break
    sleep 0.1; i=$((i+1))
  done

  [ -n "$CONF" ] && umount "$CONF" 2>/dev/null
  rm -rf "$MOUNT_STAGE"

  setprop vendor.usb.config "$(cat "$RUN/vendor-config" 2>/dev/null)" 2>/dev/null
  DATA=$(echo "$SAVED_FN" | sed 's/,adb//;s/adb,//;s/^adb$//;s/^none$//')
  settings put global adb_enabled "${SAVED_ADB:-0}" 2>/dev/null
  [ -n "$DATA" ] && svc usb setFunctions "$DATA" >/dev/null 2>&1
  if [ "${SAVED_ADB:-0}" = 1 ]; then setprop ctl.start adbd 2>/dev/null; else setprop ctl.stop adbd 2>/dev/null; fi

  echo "FRAMEWORK_RESTORE ${SAVED_ADB:-0} ${SAVED_FN:-none}"
  rm -rf "$RUN"
  return 0
}

case "$1" in
  detect)
    have_payload || { echo "NO_PAYLOAD"; exit 3; }
    CONF=$(find_conf)
    if [ -n "$CONF" ]; then
      [ -e /dev/usb-ffs/qxr/ep0 ] && { echo "BACKEND=vendor_qxr"; exit 0; }
    fi
    generic_capable && { echo "BACKEND=generic_configfs"; exit 0; }
    echo "UNSUPPORTED"; exit 3
    ;;

  start)
    MODE=${2:-closed}
    PROFILE=${3:-none}
    have_payload || { echo "NO_PAYLOAD"; exit 3; }
    [ -d "$RUN" ] && do_restore
    rm -rf "$RUN"
    save_state || { echo "STATE_FAIL"; exit 3; }
    trap 'do_restore' EXIT

    touch "$RUN/watchdog.armed"
    nohup sh -c 'sleep 120; R='"$RUN"'; [ -e "$R/watchdog.armed" ] && { kill $(cat "$R/daemon.pid" 2>/dev/null) 2>/dev/null; }' \
      >/dev/null 2>&1 < /dev/null &

    BACKEND=${4:-auto}
    case "$BACKEND" in
      vendor_qxr)
        CONF=$(find_conf); [ -n "$CONF" ] || { echo "NO_CONF"; exit 3; }
        qxr_prepare "$CONF" || { echo "PREPARE_FAIL"; exit 3; }
        ;;
      generic_configfs)
        generic_prepare || { echo "PREPARE_FAIL"; exit 3; }
        ;;
      *)
        CONF=$(find_conf)
        if [ -n "$CONF" ] && [ -e /dev/usb-ffs/qxr/ep0 ]; then
          qxr_prepare "$CONF" || { echo "PREPARE_FAIL"; exit 3; }
        else
          generic_prepare || { echo "PREPARE_FAIL"; exit 3; }
        fi
        ;;
    esac

    echo STARTED
    ATTEMPTS=20
    [ "$MODE" != pair ] || ATTEMPTS=120
    RES=TIMEOUT
    i=0
    while [ $i -lt "$ATTEMPTS" ]; do
      if [ -s "$RUN/auth-result" ]; then
        RES=$(cat "$RUN/auth-result")
        if [ "$MODE" = pair ]; then
          case "$RES" in
            PAIRED\|*|KNOWN\|*) ;;
            *) RES=TIMEOUT; sleep 0.5; i=$((i+1)); continue ;;
          esac
        fi
        sleep 0.5
        break
      fi
      sleep 0.5; i=$((i+1))
    done

    do_restore
    trap - EXIT
    printf 'AUTH_RESULT %s\n' "$RES"
    ;;

  restore) do_restore ;;

  list)
    have_payload || { echo "NO_PAYLOAD"; exit 3; }
    CLASSPATH="$APK" app_process /system/bin "$DAEMON_CLASS" list "$HOSTS"
    ;;

  edit)
    have_payload || { echo "NO_PAYLOAD"; exit 3; }
    CLASSPATH="$APK" app_process /system/bin "$DAEMON_CLASS" edit "$HOSTS" "${2:-}" "${3:-}"
    ;;

  delete)
    ID=$2
    echo "$ID" | grep -qE '^[0-9a-f]{64}$' || { echo "BAD_ID"; exit 2; }
    rm -f "$HOSTS/$ID.properties" "$HOSTS/$ID.entry"
    echo DELETED
    ;;

  *)
    echo "usage: usbauth.sh detect|start <closed|pair> [profile] [backend]|restore|list|edit|delete"
    exit 2
    ;;
esac
