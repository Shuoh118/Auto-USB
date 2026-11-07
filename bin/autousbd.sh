#!/system/bin/sh
SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
. "$SELF/../bin/autousb.sh"

cfg_load

echo "$$" > "$PIDFILE"
log 1 "daemon start | lock=$LOCK_ENABLED/${LOCK_PROFILE:-} | auto=${ON_CONNECT:-} | persist=$PERSIST"

PREV=$(usb_link_state)
APPLIED=""

while :; do
  [ -f "$MODDIR/disable" ] && { log 1 "disable flag present, exit"; break; }

  NOW=$(usb_link_state)

  if [ "$NOW" != "$PREV" ]; then
    log 2 "state: $PREV -> $NOW"
    PREV=$NOW
    sleep "${DEBOUNCE:-2}"
    NOW=$(usb_link_state)
  fi

  if [ "${LOCK_ENABLED:-0}" = "1" ]; then
    if [ "$NOW" = "configured" ] || [ "$NOW" = "powered" ]; then
      # adb_enabled 只在连上的第一轮压一次，之后交给 enforce_lock 管组合。
      # 每秒 settings put 是 IPC，白烧电。
      if [ "$APPLIED" != "lock-on" ]; then
        apply_adb "$ADB_ON_CONNECT"
        APPLIED=lock-on
      fi
      enforce_lock && log 1 "lock re-asserted"
    else
      APPLIED=""
    fi
    sleep "${POLL_INTERVAL:-1}"
    continue
  fi

  case "$NOW" in
    configured)
      [ "$APPLIED" = "on" ] && { sleep "${POLL_INTERVAL:-1}"; continue; }

      log 1 "host configured, deciding profile"
      TARGET_PROFILE="$ON_CONNECT"

      apply_adb "$ADB_ON_CONNECT"
      TARGET=$(resolve_target "$TARGET_PROFILE")

      CUR=$(current_functions)
      if [ "$(norm "$CUR")" = "$(norm "$TARGET")" ]; then
        log 1 "composition already ${TARGET:-<none>}, no-op"
      else
        log 1 "composition ${CUR:-<none>} -> ${TARGET:-<none>}"
        apply_profile "${TARGET:-none}"
        sleep 1
        # 部分 OEM 的 HAL 会吃掉第一条请求，补一次
        [ "$(norm "$(current_functions)")" = "$(norm "$TARGET")" ] || apply_profile "${TARGET:-none}"
      fi

      APPLIED=on
      echo "on" > "$STATEFILE"
      ;;

    powered)
      [ "$APPLIED" = "powered" ] && { sleep "${POLL_INTERVAL:-1}"; continue; }
      log 1 "cable in, no host enumerating (charger) — nothing to do"
      APPLIED=powered
      echo "powered" > "$STATEFILE"
      ;;

    *)
      [ "$APPLIED" = "off" ] && { sleep "${POLL_INTERVAL:-1}"; continue; }
      log 1 "cable out"
      case "${ON_DISCONNECT:-keep}" in
        restore)
          apply_adb "$ADB_ON_DISCONNECT"
          apply_profile "$OFF_PROFILE"
          ;;
        none)
          apply_adb "$ADB_ON_DISCONNECT"
          apply_profile none
          ;;
        *) : ;;
      esac
      APPLIED=off
      echo "off" > "$STATEFILE"
      ;;
  esac

  sleep "${POLL_INTERVAL:-1}"
done

rm -f "$PIDFILE"
log 1 "daemon stop"
