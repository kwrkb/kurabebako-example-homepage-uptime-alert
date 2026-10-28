#!/usr/bin/env bash
# 撤収。監視 → 解析のサイト → Pages の順に消す（リポジトリは残す）。鍵は 2 つとも要る。
#   op run --env-file=uptimerobot.env.tpl -- op run --env-file=cloudflare.env.tpl -- bash scripts/teardown.sh
LOG_NAME=teardown
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
S="$ROOT/scripts"
log "=== 撤収 ==="
bash "$S/monitor.sh" delete
bash "$S/analytics.sh" delete
bash "$S/pages.sh" disable
log "=== 残るのはリポジトリだけ（消すなら GitHub の Settings から） ==="
