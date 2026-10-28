# op run --env-file=cloudflare.env.tpl -- bash scripts/analytics.sh create
# トークンの権限: Account Settings Write（作成・削除）、Account Settings Read（一覧）、Account Analytics Read（GraphQL）
# 1Password を使わないなら、環境変数 CF_API_TOKEN と CF_ACCOUNT_ID を直接 export する
CF_API_TOKEN="op://kurabebako/kurabebako-example-homepage-uptime-alert/api_key"
CF_ACCOUNT_ID="op://kurabebako/kurabebako-example-homepage-uptime-alert/account_id"
