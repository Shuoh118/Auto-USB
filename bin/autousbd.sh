#!/system/bin/sh

SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
[ -f "$SELF/../bin/autousb.sh" ] || SELF=/data/adb/modules/autousb/bin
[ -f "$SELF/../bin/autousb.sh" ] || { echo "NO_LIB"; exit 3; }
. "$SELF/../bin/autousb.sh"

cfg_load

echo "$$" > "$PIDFILE" 2>/dev/null
log 1 "daemon start | lock=$LOCK_ENABLED/${LOCK_PROFILE:-} | auto=${ON_CONNECT:-} | persist=$PERSIST"

PREV=$(usb_link_state)
APPLIED=""
TICKS=0
# 启动时已经拔线就别动系统：否则每次开机都会把用户手动选的组合改回 OFF_PROFILE
case "$PREV" in
  configured|powered) : ;;
  *) APPLIED=off ;;
esac

while :; do
  if [ -f "$MODDIR/disable" ]; then
    log 1 "disable flag present, exit"
    break
  fi

  NOW=$(usb_link_state)

  # 上一次套用没生效时退避重试，避免每秒轰炸 HAL 把 USB 反复重置
  if [ "$APPLIED" = "apply-retry" ]; then
    TICKS=$((TICKS + 1))
    if [ "$TICKS" -lt "${LOCK_REASSERT:-5}" ]; then
      sleep "${POLL_INTERVAL:-1}"
      continue
    fi
    APPLIED=""
    TICKS=0
  fi

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
        TICKS=0
        enforce_lock && log 1 "lock applied"
      else
        # current_functions 要扫 configfs，隔几秒再核对一次就够
        TICKS=$((TICKS + 1))
        if [ "$TICKS" -ge "${LOCK_REASSERT:-5}" ]; then
          TICKS=0
          enforce_lock && log 1 "lock re-asserted"
        fi
      fi
    else
      APPLIED=""
      TICKS=0
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
      if fns_equal "$CUR" "$TARGET"; then
        log 1 "composition already ${TARGET:-<none>}, no-op"
        APPLIED=on
      else
        log 1 "composition ${CUR:-<none>} -> ${TARGET:-<none>}"
        apply_profile "${TARGET:-none}"
        sleep 1
        # 部分 OEM 的 HAL 会吃掉第一条请求，补一次
        fns_equal "$(current_functions)" "$TARGET" || apply_profile "${TARGET:-none}"
        sleep 1
        CUR2=$(current_functions)
        if [ -z "$CUR2" ] || fns_equal "$CUR2" "$TARGET"; then
          # 读不到就别判死，按成功处理；能读到就必须真的对上
          APPLIED=on
        else
          log 1 "apply did not take effect (${CUR2}), retry later"
          APPLIED=apply-retry
          TICKS=0
        fi
      fi

      echo "on" > "$STATEFILE" 2>/dev/null
      ;;

    powered)
      [ "$APPLIED" = "powered" ] && { sleep "${POLL_INTERVAL:-1}"; continue; }
      log 1 "cable in, no host enumerating (charger) — nothing to do"
      APPLIED=powered
      echo "powered" > "$STATEFILE" 2>/dev/null
      ;;

    *)
      [ "$APPLIED" = "off" ] && { sleep "${POLL_INTERVAL:-1}"; continue; }
      log 1 "cable out"
      case "${ON_DISCONNECT:-keep}" in
        restore)
          apply_adb "$ADB_ON_DISCONNECT"
          # 断开时也要按 ADB_ON_DISCONNECT 决定组合里带不带 adb
          apply_profile "$(resolve_target "$OFF_PROFILE" "$ADB_ON_DISCONNECT")"
          ;;
        none)
          apply_adb "$ADB_ON_DISCONNECT"
          apply_profile none
          ;;
        *) : ;;
      esac
      APPLIED=off
      echo "off" > "$STATEFILE" 2>/dev/null
      ;;
  esac

  sleep "${POLL_INTERVAL:-1}"
done

rm -f "$PIDFILE" 2>/dev/null
log 1 "daemon stop"
