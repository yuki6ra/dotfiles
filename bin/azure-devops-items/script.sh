#!/usr/bin/env bash
#
# Azure DevOps の Work Items を期間指定 & AssignedTo で検索し、
# ID / Title / URL を一覧出力するスクリプト
#
# 前提:
#   - AZDO_PAT 環境変数に Personal Access Token を設定済み
#   - curl, jq がインストールされていること
#
# 使い方:
#   ./azdo_list_my_wi.sh \
#       --org-url https://dev.azure.com/your-org \
#       --project YourProject \
#       --user "your.name@company.com" \
#       --from 2025-12-01 \
#       --to 2026-01-31 \
#       [--type Task]
#
# 出力:
#   ID<TAB>Title<TAB>URL
#   12345<tab>Implement foo feature<tab>https://dev.azure.com/...

set -euo pipefail

print_usage() {
  cat <<EOF
Usage: $0 --org-url ORG_URL --project PROJECT --user USER --from YYYY-MM-DD --to YYYY-MM-DD [--type TYPE]

Required:
  --org-url   Azure DevOps organization URL (e.g. https://dev.azure.com/your-org)
  --project   Project name
  --user      Assigned To (e.g. your.name@company.com)
  --from      Start date (YYYY-MM-DD)
  --to        End date (YYYY-MM-DD)

Optional:
  --type      Work item type to filter (e.g. Task, Bug)

Environment:
  AZDO_PAT    Personal Access Token (required)

Output:
  ID<TAB>Title<TAB>URL
EOF
}

ORG_URL=""
PROJECT=""
USER_NAME=""
DATE_FROM=""
DATE_TO=""
WORKITEM_TYPE=""

# 引数パース
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org-url)
      ORG_URL="$2"
      shift 2
      ;;
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --user)
      USER_NAME="$2"
      shift 2
      ;;
    --from)
      DATE_FROM="$2"
      shift 2
      ;;
    --to)
      DATE_TO="$2"
      shift 2
      ;;
    --type)
      WORKITEM_TYPE="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

# 入力チェック
if [[ -z "${AZDO_PAT:-}" ]]; then
  echo "Error: AZDO_PAT environment variable is not set." >&2
  exit 1
fi

if [[ -z "$ORG_URL" || -z "$PROJECT" || -z "$USER_NAME" || -z "$DATE_FROM" || -z "$DATE_TO" ]]; then
  echo "Error: Missing required arguments." >&2
  print_usage >&2
  exit 1
fi

# 簡易的な日付フォーマットチェック（YYYY-MM-DD かどうか）
if ! [[ "$DATE_FROM" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Error: --from must be in YYYY-MM-DD format." >&2
  exit 1
fi
if ! [[ "$DATE_TO" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Error: --to must be in YYYY-MM-DD format." >&2
  exit 1
fi

# オーガナイゼーション名を URL から抽出（URL の形が https://dev.azure.com/{org} 前提）
# 例: ORG_URL=https://dev.azure.com/myorg → ORG_NAME=myorg
ORG_NAME="${ORG_URL##*/}"

# WIQL の WHERE 句を組み立てる
# 期間は Changed Date ベースでフィルタする
where_clause="[System.AssignedTo] = '${USER_NAME}' AND [System.ChangedDate] >= '${DATE_FROM}' AND [System.ChangedDate] <= '${DATE_TO}'"

if [[ -n "$WORKITEM_TYPE" ]]; then
  where_clause="${where_clause} AND [System.WorkItemType] = '${WORKITEM_TYPE}'"
fi

# WIQL クエリ JSON を作成
# top 200 で上限を付けています。必要に応じて調整してください。
wiql_json=$(cat <<EOF
{
  "query": "SELECT [System.Id] FROM WorkItems WHERE ${where_clause} ORDER BY [System.ChangedDate] DESC"
}
EOF
)

# WIQL 実行
WIQL_URL="${ORG_URL}/${PROJECT}/_apis/wit/wiql?api-version=7.0"

wiql_response=$(curl -sS -w "\n%{http_code}" \
  -u ":${AZDO_PAT}" \
  -H "Content-Type: application/json" \
  -X POST \
  -d "$wiql_json" \
  "$WIQL_URL")

# HTTP ステータスコードを取り出す
http_body=$(printf "%s" "$wiql_response" | sed '$d')
http_code=$(printf "%s" "$wiql_response" | tail -n1)

if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
  echo "Error: WIQL query failed with HTTP status $http_code" >&2
  echo "Response body:" >&2
  echo "$http_body" >&2
  exit 1
fi

# ID の配列を取得
ids=$(printf "%s" "$http_body" | jq -r '.workItems[].id' 2>/dev/null || true)

if [[ -z "$ids" ]]; then
  # ヒットなし
  echo "No work items found for user '${USER_NAME}' between ${DATE_FROM} and ${DATE_TO}." >&2
  exit 0
fi

# カンマ区切りに変換
id_list=$(printf "%s\n" "$ids" | paste -sd "," -)

# Work Item 詳細取得
WI_URL="${ORG_URL}/${PROJECT}/_apis/wit/workitems?ids=${id_list}&api-version=7.0"

wi_response=$(curl -sS -w "\n%{http_code}" \
  -u ":${AZDO_PAT}" \
  "$WI_URL")

wi_body=$(printf "%s" "$wi_response" | sed '$d')
wi_code=$(printf "%s" "$wi_response" | tail -n1)

if [[ "$wi_code" -lt 200 || "$wi_code" -ge 300 ]]; then
  echo "Error: Work items fetch failed with HTTP status $wi_code" >&2
  echo "Response body:" >&2
  echo "$wi_body" >&2
  exit 1
fi

# 出力: ID<TAB>Title<TAB>URL
# URL 形式: https://dev.azure.com/{org}/{project}/_workitems/edit/{id}
printf "%s" "$wi_body" | jq -r --arg org "$ORG_NAME" --arg project "$PROJECT" '
  .value[] | 
  [.id, .fields["System.Title"], ("https://dev.azure.com/" + $org + "/" + $project + "/_workitems/edit/" + (.id|tostring))] |
  @tsv
'
