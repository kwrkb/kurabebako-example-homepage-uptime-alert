#!/usr/bin/env bash
# Cloudflare Web Analytics を API トークンだけで扱う。サイトの作成 → ビーコンを index.html に書く → GraphQL で訪問数を読む → 削除。
# 環境変数: CF_API_TOKEN（Account Settings Write / Account Settings Read / Account Analytics Read）、CF_ACCOUNT_ID
#   op run --env-file=cloudflare.env.tpl -- bash scripts/analytics.sh create   サイトを作り、site_tag を runs/state.json に控え、index.html のビーコン行を書き換える
#   op run --env-file=cloudflare.env.tpl -- bash scripts/analytics.sh query    state の site_tag で直近 7 日のページロード数を読む
#   op run --env-file=cloudflare.env.tpl -- bash scripts/analytics.sh delete   state の site_tag のサイトを消す
# API トークンの値は出力しない。site_token はページに載る公開値なので index.html には書くが、ログには出さない。
LOG_NAME=analytics
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
: "${CF_API_TOKEN:?CF_API_TOKEN が未設定（op run で注入する）}"
: "${CF_ACCOUNT_ID:?CF_ACCOUNT_ID が未設定}"
MODE=${1:-query}
CF=https://api.cloudflare.com/client/v4
AUTH="Authorization: Bearer $CF_API_TOKEN"
HOST="$OWNER.github.io"          # Pages のホスト名。パス（/<repo>/）は登録しない
PLACEHOLDER='<!-- cf-beacon:'

cf() { http "$1" "$CF$2" "$AUTH" "${3:-}"; }

verify() {
  local v; v=$(cf GET /user/tokens/verify)
  jq -e .success <<<"$v" >/dev/null || { log "token verify failed: $(jq -c .errors <<<"$v")"; exit 1; }
  log "token: status=$(jq -r .result.status <<<"$v") expires_on=$(jq -r '.result.expires_on // "-"' <<<"$v")"
}

case "$MODE" in
  create)
    log "--- Cloudflare Web Analytics のサイトを作る（host=$HOST） ---"
    verify
    r=$(cf POST "/accounts/$CF_ACCOUNT_ID/rum/site_info" "$(jq -nc --arg h "$HOST" '{host:$h, auto_install:false}')")
    jq -e .success <<<"$r" >/dev/null || { log "create failed: $(jq -c .errors <<<"$r")"; exit 1; }
    tag=$(jq -r .result.site_tag <<<"$r"); token=$(jq -r .result.site_token <<<"$r")
    state_set site_tag "$tag"
    log "site_tag=$tag created=$(jq -r .result.created <<<"$r") keys=$(jq -r '.result | keys | join(",")' <<<"$r")"
    # ビーコン: docs の手動設置の形。応答に snippet は入っていないので自分で組む
    beacon="<script defer src=\"https://static.cloudflareinsights.com/beacon.min.js\" data-cf-beacon='{\"token\": \"$token\"}'></script>"
    if grep -q "$PLACEHOLDER" "$ROOT/index.html"; then
      python - "$ROOT/index.html" "$beacon" <<'PY'
import sys, re
path, beacon = sys.argv[1], sys.argv[2]
s = open(path, encoding="utf-8").read()
s = re.sub(r"  <!-- cf-beacon:[^\n]*\n", "  " + beacon.replace("\\", "\\\\") + "\n", s, count=1)
open(path, "w", encoding="utf-8", newline="\n").write(s)
PY
      log "index.html のビーコン行を書き換えた（commit は人が確認してから）"
    else
      log "index.html にプレースホルダーが無い。ビーコン行は手で置く"
    fi
    ;;
  query)
    tag=$(state_get site_tag); [ -n "$tag" ] || { log "state に site_tag が無い"; exit 1; }
    since=$(python -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
    until=$(python -c 'import datetime as d; print(d.datetime.now(d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')
    q=$(jq -cn --arg a "$CF_ACCOUNT_ID" --arg t "$tag" --arg s "$since" --arg u "$until" '{query:"query($a:String!,$t:String!,$s:Time!,$u:Time!){ viewer { accounts(filter:{accountTag:$a}) { rumPageloadEventsAdaptiveGroups(limit:10, filter:{siteTag:$t, datetime_geq:$s, datetime_leq:$u}) { count sum { visits } avg { sampleInterval } } } } }", variables:{a:$a,t:$t,s:$s,u:$u}}')
    r=$(cf POST /graphql "$q")
    log "pageloads(7d): $(jq -c '.data.viewer.accounts[0].rumPageloadEventsAdaptiveGroups // .errors' <<<"$r")"
    ;;
  delete)
    tag=$(state_get site_tag); [ -n "$tag" ] || { log "state に site_tag が無い"; exit 1; }
    r=$(cf DELETE "/accounts/$CF_ACCOUNT_ID/rum/site_info/$tag")
    log "delete: success=$(jq -r .success <<<"$r") errors=$(jq -c .errors <<<"$r")"
    ;;
  *) echo "usage: analytics.sh create|query|delete" >&2; exit 2 ;;
esac
