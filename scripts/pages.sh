#!/usr/bin/env bash
# GitHub Pages を REST API で有効化 / 無効化し、実際に配信されるまでを追う。認証は gh CLI のもの（repo スコープ）。
#   bash scripts/pages.sh enable    POST /repos/{owner}/{repo}/pages（main の / をそのまま配信）→ ビルド完了 → URL が 200 になるまで
#   bash scripts/pages.sh disable   DELETE /repos/{owner}/{repo}/pages → URL が 404 になるまで
#   bash scripts/pages.sh status    GET  /repos/{owner}/{repo}/pages と builds/latest を表示するだけ
LOG_NAME=pages
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
MODE=${1:-status}
API="repos/$OWNER/$REPO/pages"

show() {
  local p b
  p=$(gh api "$API" 2>/dev/null || echo '{}')
  b=$(gh api "$API/builds/latest" 2>/dev/null || echo '{}')
  log "pages: status=$(jq -r '.status // "none"' <<<"$p") html_url=$(jq -r '.html_url // "-"' <<<"$p") build=$(jq -r '.status // "-"' <<<"$b") build_error=$(jq -r '.error.message // "-"' <<<"$b")"
}

# site_status が期待のコードになるまで 15 秒おきに待つ（最大 10 分）
wait_site() {
  local want=$1 i code
  for i in $(seq 1 40); do
    code=$(site_status)
    log "site: GET $SITE_URL -> $code"
    [ "$code" = "$want" ] && return 0
    sleep 15
  done
  log "site が $want にならなかった"; return 1
}

case "$MODE" in
  enable)
    log "--- GitHub Pages を有効化する（build_type=legacy, source=main:/） ---"
    local_t0=$(ms)
    if r=$(gh api -X POST "$API" -f build_type=legacy -f 'source[branch]=main' -f 'source[path]=/' 2>&1); then
      log "POST $API -> 201 html_url=$(jq -r .html_url <<<"$r")"
    else
      log "POST $API -> 失敗（既に有効なら 409）: $(printf '%s' "$r" | tr -d '\n' | cut -c1-160)"
    fi
    for i in $(seq 1 20); do
      st=$(gh api "$API" --jq .status 2>/dev/null || echo none)
      log "pages.status=$st"
      [ "$st" = built ] && break
      sleep 15
    done
    show
    wait_site 200
    log "有効化から 200 まで $(( ( $(ms) - local_t0 ) / 1000 )) 秒"
    ;;
  disable)
    log "--- GitHub Pages を無効化する（DELETE） ---"
    local_t0=$(ms)
    if gh api -X DELETE "$API" >/dev/null 2>&1; then log "DELETE $API -> 204"; else log "DELETE $API -> 失敗（無効なら 404）"; fi
    wait_site 404
    log "無効化から 404 まで $(( ( $(ms) - local_t0 ) / 1000 )) 秒"
    ;;
  status) show; log "site: GET $SITE_URL -> $(site_status)" ;;
  *) echo "usage: pages.sh enable|disable|status" >&2; exit 2 ;;
esac
