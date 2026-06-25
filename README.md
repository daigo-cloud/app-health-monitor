# app-health-monitor

エスコ主要アプリ(Azure App Service / Static Web Apps)の死活監視。
GitHub Actions が **15分毎** に各アプリへHTTPアクセスし、**異常検知/復旧の瞬間だけ** Teams に通知します(平常時は無通知)。

- 判定: 正常 = HTTP `2xx/3xx/401/403`、異常 = `5xx` もしくは無応答(`000`)
- 通知: Teams Incoming Webhook(MessageCard)
- 状態保持: GitHub Actions キャッシュ(実行間で前回状態を保持し「変化時のみ通知」)

## 設定(リポジトリ Secrets)

| Secret | 内容 |
|---|---|
| `MONITOR_TARGETS` | 監視対象。1行 `表示名\|URL`(改行区切り) |
| `TEAMS_WEBHOOK` | 通知先 Teams Incoming Webhook URL |

> 内部情報(アプリURL一覧・Webhook)はすべて暗号化 Secret に格納。コード・実行ログには出しません。

## 手動実行

Actions タブ → **App Health Monitor** → **Run workflow**

## 監視対象の追加・変更

`MONITOR_TARGETS` Secret を編集するだけ(コード変更不要)。
