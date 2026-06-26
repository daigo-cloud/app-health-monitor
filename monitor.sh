#!/usr/bin/env bash
# monitor.sh — エスコ主要アプリのヘルス監視→異常/復旧時のみTeams通知
#
# 入力(環境変数):
#   MONITOR_TARGETS  改行区切りで "表示名|URL"(1行1アプリ)
#   TEAMS_WEBHOOK    Teams の Workflows Webhook URL(投稿先=⚙インフラ運用ch)
# 状態:
#   ./state/health-state.tsv  (GitHub Actions のキャッシュで実行間を跨いで保持)
#
# 判定: 正常=HTTP 2xx/3xx/401/403、異常=5xx もしくは無応答(000)。
# 通知: 状態が変化した時(正常→異常 / 異常→復旧)だけ投稿。平常時は無通知。
# 形式: Adaptive Card を {type:message, attachments:[...]} で包む(Workflows仕様)。
set -uo pipefail

STATE_DIR="${STATE_DIR:-./state}"
STATE_FILE="$STATE_DIR/health-state.tsv"
mkdir -p "$STATE_DIR"; touch "$STATE_FILE"
NOW="$(date '+%Y-%m-%d %H:%M:%S %Z')"

prev_state() { grep -F "$1	" "$STATE_FILE" 2>/dev/null | head -1 | cut -f2; }
is_up() { case "$1" in 2[0-9][0-9]|3[0-9][0-9]|401|403) return 0;; *) return 1;; esac; }

CHANGES=""        # Teams本文(Adaptive Card textに渡す)
HAS_DOWN=0
IDX=0
NEW_STATE="$(mktemp)"

while IFS='|' read -r NAME URL; do
  NAME="$(printf '%s' "$NAME" | xargs)"; URL="$(printf '%s' "$URL" | xargs)"
  [ -z "$NAME" ] && continue
  [ -z "$URL" ] && continue

  CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$URL" 2>/dev/null)"
  if is_up "$CODE"; then CUR="UP"; else CUR="DOWN"; fi

  PREV="$(prev_state "$NAME")"; [ -z "$PREV" ] && PREV="UP"   # 初回は正常前提(初報の誤検知防止)
  IDX=$((IDX+1))
  echo "target #${IDX}: code=$CODE status=$CUR"   # 公開ログに内部情報(名前/URL)は出さない

  if [ "$CUR" != "$PREV" ]; then
    if [ "$CUR" = "DOWN" ]; then
      HAS_DOWN=1
      CHANGES="${CHANGES}🔴 **${NAME}** 異常検知 (HTTP ${CODE}) — ${URL}"$'\n\n'
    else
      CHANGES="${CHANGES}🟢 **${NAME}** 復旧 (HTTP ${CODE}) — ${URL}"$'\n\n'
    fi
  fi
  printf '%s\t%s\n' "$NAME" "$CUR" >> "$NEW_STATE"
done <<< "$MONITOR_TARGETS"

mv "$NEW_STATE" "$STATE_FILE"

if [ -z "$CHANGES" ]; then
  echo "全アプリ正常(状態変化なし) — 通知なし"
  exit 0
fi

COLOR="good"; [ "$HAS_DOWN" = "1" ] && COLOR="attention"
TITLE="🚨 アプリ監視アラート"

# Adaptive Card を Workflows 仕様で組み立て(jqで安全にエスケープ)
PAYLOAD="$(jq -n \
  --arg title "$TITLE" --arg ts "$NOW" --arg body "$CHANGES" --arg color "$COLOR" '
  {
    type: "message",
    attachments: [{
      contentType: "application/vnd.microsoft.card.adaptive",
      content: {
        type: "AdaptiveCard",
        "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
        version: "1.4",
        body: [
          { type:"TextBlock", text:$title, weight:"Bolder", size:"Large", color:$color },
          { type:"TextBlock", text:$ts, isSubtle:true, spacing:"None", wrap:true },
          { type:"TextBlock", text:$body, wrap:true }
        ]
      }
    }]
  }')"

if [ -z "${TEAMS_WEBHOOK:-}" ]; then
  echo "::warning::TEAMS_WEBHOOK 未設定、投稿スキップ"
  exit 0
fi

HC="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "$PAYLOAD" "$TEAMS_WEBHOOK" 2>/dev/null)"
echo "Teams投稿: HTTP $HC"
# Workflows は受理時 200/202 を返す
case "$HC" in 200|202) : ;; *) echo "::error::Teams投稿失敗 (HTTP $HC)"; exit 1;; esac
