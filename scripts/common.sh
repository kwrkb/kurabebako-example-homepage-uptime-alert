#!/usr/bin/env bash
# 各スクリプトが source する共通部分。ログの置き場・状態ファイル・HTTP 呼び出しの薄い包み。
# 鍵の値は一切出力しない（ヘッダーに載せるだけ）。ログは runs/ に残し、リポジトリに含める（記事から証拠としてリンクする）。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OWNER=${OWNER:-kwrkb}
REPO=${REPO:-kurabebako-example-homepage-uptime-alert}
SITE_URL="https://$OWNER.github.io/$REPO/"
MONITOR_NAME="$REPO"

RUNS="$ROOT/runs"
mkdir -p "$RUNS"
STATE="$RUNS/state.json"                     # monitor_id / site_tag / incident_id など、秘密ではない識別子の控え
LOG="$RUNS/${LOG_NAME:-run}-$(date -u +%Y%m%d-%H%M).log"
HDR=$(mktemp)
trap 'rm -f "$HDR"' EXIT

# stderr に出す。関数の戻り値（stdout）にログが混ざると jq が壊れるため
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOG" >&2; }
ms() { python -c 'import time; print(int(time.time()*1000))'; }

state_get() { [ -f "$STATE" ] && jq -r --arg k "$1" '.[$k] // empty' "$STATE" || true; }
state_set() {
  local tmp; tmp=$(mktemp)
  if [ -f "$STATE" ]; then jq --arg k "$1" --arg v "$2" '.[$k] = $v' "$STATE" > "$tmp"; else jq -n --arg k "$1" --arg v "$2" '{($k): $v}' > "$tmp"; fi
  mv "$tmp" "$STATE"
}

# http <METHOD> <URL> <AUTH ヘッダー> [JSON] → 本文を stdout。ステータスと所要時間はログへ
http() {
  local method=$1 url=$2 auth=$3 body=${4:-}
  local args=(-s -D "$HDR" -X "$method" -H "$auth" -H "Content-Type: application/json" -H "Accept: application/json")
  [ -n "$body" ] && args+=(-d "$body")
  local t0 out status; t0=$(ms)
  out=$(curl "${args[@]}" "$url")
  status=$(head -1 "$HDR" | awk '{print $2}')
  # ログに残す URL からアカウント ID を伏せる（op run が隠すのは標準出力だけで、ファイルには素で残るため）
  local shown=${url#https://}
  [ -n "${CF_ACCOUNT_ID:-}" ] && shown=${shown//$CF_ACCOUNT_ID/<account_id>}
  log "$method $shown -> $status ($(( $(ms) - t0 )) ms)"
  printf '%s' "$out"
}

# サイトの HTTP ステータスだけを返す（本文は捨てる）
site_status() { curl -s -o /dev/null -w '%{http_code}' -H "Cache-Control: no-cache" "$SITE_URL"; }
