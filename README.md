# kurabebako-example-homepage-uptime-alert

[kurabebako](https://kurabebako.com/) の作例 1 本目「AI にホームページを公開して、止まったら知らせてもらう」の成果物。
解説と判断の理由は [作例の記事](https://kurabebako.com/examples/homepage-uptime-alert/)、動いている現物は
[公開ページ](https://kwrkb.github.io/kurabebako-example-homepage-uptime-alert/)。

作ったのは Claude、判断と確認は人間が行いました。

## 何が動いているか

| 部品 | 役割 | 操作した API |
| --- | --- | --- |
| GitHub Pages | `main` の HTML をそのまま配信する | `POST /repos/{owner}/{repo}/pages`（`scripts/pages.sh`） |
| UptimeRobot（Free） | 5 分おきに公開ページを見に来て、止まったらメールで知らせる | API v3 `POST /monitors` + `assignedAlertContacts`（`scripts/monitor.sh`） |
| Cloudflare Web Analytics | ページ末尾の 1 行のタグで訪問を数える。Cookie なし | `POST /accounts/{id}/rum/site_info` + GraphQL（`scripts/analytics.sh`） |

実行ログは `runs/` にそのまま置いてあります（鍵とメールアドレスは出していません）。
`scripts/outage.sh` は Pages を一度無効化して DOWN → メール通知 → 再公開 → UP の一巡を起こし、
通知が送られた事実を `GET /incidents/{id}/alerts` で記録します。

## 同じものを自分の環境で動かす

1. このリポジトリを fork し、`scripts/common.sh` の `OWNER` を自分のユーザー名にする（またはスクリプト実行時に `OWNER=<名前>` を渡す）
2. 鍵を 2 つ用意する: UptimeRobot の Main API key（ダッシュボード → Integrations & API）と、
   Cloudflare の API トークン（Account Settings Write / Account Settings Read / Account Analytics Read）＋アカウント ID。
   1Password を使うなら `uptimerobot.env.tpl` / `cloudflare.env.tpl` の `op://` 参照を自分の vault に合わせる。使わないなら環境変数を export する
3. 順に実行する（`gh auth login` 済みの前提）

   ```bash
   bash scripts/pages.sh enable                                            # 公開
   op run --env-file=cloudflare.env.tpl  -- bash scripts/analytics.sh create   # 解析のサイトを作り、index.html にビーコンを書く → commit / push
   op run --env-file=uptimerobot.env.tpl -- bash scripts/monitor.sh create     # 監視を作り、UP を確認
   ```

撤収は `bash scripts/teardown.sh`（両方の鍵が要る）。リポジトリだけが残ります。

## 前提

- `bash`、`curl`、`jq`、`python`（3 系）、`gh`。Windows は Git for Windows の bash で動かしています
- GitHub Pages は公開リポジトリで無料。商取引が主目的のサイトには使えません（GitHub の利用規約）
- UptimeRobot の無料プランは 5 分間隔、通知先はメールなど。`threshold` と `recurrence` は 0 固定
- Cloudflare Web Analytics は無料で、参照できるのは直近 6 か月

## ライセンス

MIT
