#!/usr/bin/env bash
# UptimeRobot API v3 で HTTP モニターを作り、メールの通知先を付け、初回チェックが UP になるまで追う。
# 環境変数: UPTIMEROBOT_API_KEY（Main API key。無料プランで使える）
#   op run --env-file=uptimerobot.env.tpl -- bash scripts/monitor.sh create   通知先の一覧 → モニター作成（300 秒間隔、threshold/recurrence は無料枠の 0）→ UP まで
#   op run --env-file=uptimerobot.env.tpl -- bash scripts/monitor.sh status   state の monitor_id の状態を 1 回だけ表示
#   op run --env-file=uptimerobot.env.tpl -- bash scripts/monitor.sh delete   state の monitor_id を消す
# 通知先の選び方: type が Email のものを 1 つ（環境変数 ALERT_CONTACT_ID で指定してもよい）。メールアドレスはログに出さない。
LOG_NAME=monitor
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
: "${UPTIMEROBOT_API_KEY:?UPTIMEROBOT_API_KEY が未設定（op run で注入する）}"
MODE=${1:-status}
UR=https://api.uptimerobot.com/v3
AUTH="Authorization: Bearer $UPTIMEROBOT_API_KEY"

ur() { http "$1" "$UR$2" "$AUTH" "${3:-}"; }

case "$MODE" in
  create)
    log "--- 通知先を選ぶ ---"
    contacts=$(ur GET /user/alert-contacts)
    log "alert contacts: $(jq -c '[.[] | {id, type, name: (.friendlyName // "-")}]' <<<"$contacts")"
    cid=${ALERT_CONTACT_ID:-$(jq -r '[.[] | select((.type|tostring|ascii_downcase) | test("mail"))][0].id // empty' <<<"$contacts")}
    [ -n "$cid" ] || { log "メールの通知先が見つからない。ALERT_CONTACT_ID で指定する"; exit 1; }
    log "use alert contact id=$cid"

    log "--- モニターを作る（HTTP, 300 秒, $SITE_URL） ---"
    body=$(jq -nc --arg u "$SITE_URL" --arg n "$MONITOR_NAME" --argjson c "$cid" \
      '{type:"HTTP", url:$u, friendlyName:$n, interval:300, timeout:30, httpMethodType:"GET", checkSSLErrors:true,
        assignedAlertContacts:[{alertContactId:$c, threshold:0, recurrence:0}]}')
    r=$(ur POST /monitors "$body")
    mid=$(jq -r '.id // empty' <<<"$r")
    [ -n "$mid" ] || { log "作成に失敗: $(jq -c '{message: .message?, errors: .errors?}' <<<"$r")"; exit 1; }
    state_set monitor_id "$mid"
    log "created: id=$mid status=$(jq -r .status <<<"$r") interval=$(jq -r .interval <<<"$r") contacts=$(jq -c '[.assignedAlertContacts[]? | {alertContactId, threshold, recurrence}]' <<<"$r")"

    log "--- 初回チェックが反映されるまで追う（最大 8 分） ---"
    for i in $(seq 1 8); do
      r=$(ur GET "/monitors/$mid")
      st=$(jq -r .status <<<"$r")
      log "poll $i: status=$st"
      case "$st" in UP|DOWN|up|down) break;; esac
      sleep 60
    done
    ;;
  status)
    mid=$(state_get monitor_id); [ -n "$mid" ] || { log "state に monitor_id が無い"; exit 1; }
    r=$(ur GET "/monitors/$mid")
    log "monitor $mid: $(jq -c '{friendlyName, status, interval, url}' <<<"$r")"
    ;;
  delete)
    mid=$(state_get monitor_id); [ -n "$mid" ] || { log "state に monitor_id が無い"; exit 1; }
    r=$(ur DELETE "/monitors/$mid")
    log "delete $mid: $(printf '%s' "$r" | tr -d '\n' | cut -c1-120)"
    ;;
  *) echo "usage: monitor.sh create|status|delete" >&2; exit 2 ;;
esac
