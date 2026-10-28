#!/usr/bin/env bash
# 「止まったら知らせてもらう」を実際に起こす。Pages を無効化して 404 にし、UptimeRobot が DOWN を検知して通知を送るまで追い、
# 再公開して UP に戻るまでを記録する。通知が送られた事実は /incidents/{id}/alerts（送信先と配信状態）で API から確かめる。
# 環境変数: UPTIMEROBOT_API_KEY。GitHub は gh CLI の認証。
#   op run --env-file=uptimerobot.env.tpl -- bash scripts/outage.sh
LOG_NAME=outage
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
: "${UPTIMEROBOT_API_KEY:?UPTIMEROBOT_API_KEY が未設定（op run で注入する）}"
UR=https://api.uptimerobot.com/v3
AUTH="Authorization: Bearer $UPTIMEROBOT_API_KEY"
PAGES="$ROOT/scripts/pages.sh"
ur() { http "$1" "$UR$2" "$AUTH" "${3:-}"; }

mid=$(state_get monitor_id); [ -n "$mid" ] || { log "state に monitor_id が無い（先に monitor.sh create）"; exit 1; }

# モニターの status が want になるまで 30 秒おきに待つ（最大 20 分）
wait_monitor() {
  local want=$1 i st
  for i in $(seq 1 40); do
    st=$(ur GET "/monitors/$mid" | jq -r .status)
    log "monitor: status=$st"
    [ "${st^^}" = "$want" ] && return 0
    sleep 30
  done
  log "monitor が $want にならなかった"; return 1
}

# 直近の incident と、その incident で送られた通知（送信先の値は伏せる）
show_alerts() {
  local inc id
  inc=$(ur GET "/incidents?monitor_id=$mid")
  id=$(jq -r '.data[0].id // empty' <<<"$inc")
  [ -n "$id" ] || { log "incident が無い"; return 0; }
  state_set incident_id "$id"
  log "incident $id: $(jq -c '.data[0] | {status, reason, startedAt, resolvedAt, duration}' <<<"$inc")"
  log "alerts: $(ur GET "/incidents/$id/alerts" | jq -c '[.data[] | {timestamp, channelType, recipientName, status}]')"
}

st=$(ur GET "/monitors/$mid" | jq -r .status)
log "=== 開始。monitor $mid status=$st ==="
[ "${st^^}" = UP ] || { log "UP でないので始めない"; exit 1; }

t0=$(ms)
log "--- 1. Pages を無効化して 404 にする ---"
bash "$PAGES" disable
t_down_site=$(ms)
log "--- 2. UptimeRobot が DOWN を検知するまで ---"
wait_monitor DOWN
t_down_detect=$(ms)
log "検知まで $(( (t_down_detect - t_down_site) / 1000 )) 秒（404 になってから）"
sleep 60   # 通知の送信記録が揃うのを少し待つ
show_alerts

log "--- 3. 再公開して UP に戻るまで ---"
bash "$PAGES" enable
t_up_site=$(ms)
wait_monitor UP
t_up_detect=$(ms)
log "復旧の検知まで $(( (t_up_detect - t_up_site) / 1000 )) 秒（200 に戻ってから）"
sleep 60
show_alerts
log "=== 終了。全体 $(( (t_up_detect - t0) / 1000 )) 秒 ==="
