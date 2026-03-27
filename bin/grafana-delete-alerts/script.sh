#!/bin/bash

set -euo pipefail

#================================================================
# Import Config
#================================================================
source ./config.sh

#================================================================
# Function
#================================================================
get_folder_uid() {
	local grafana_url=${1}
	local sa_token=${2}
	local get_folder_name=${3}

	local folder_info
	folder_info=$(curl -s -X GET "https://${grafana_url}/api/folders" \
		-H "Authorization: Bearer ${sa_token}")

	local folder_uid
	folder_uid=$(echo "$folder_info" |
		jq -r --arg name "$get_folder_name" '.[] | select(.title == $name) | .uid')

	echo "$folder_uid"
}

get_alert_uids() {
	local grafana_url=${1}
	local sa_token=${2}
	local target_folder_uid=${3}
	local rule_groups=${4}

	# 変数に格納せず直接パイプ
	curl -s -X GET "https://${grafana_url}/api/v1/provisioning/alert-rules" \
		-H "Authorization: Bearer ${sa_token}" |
		jq -r --arg folder_uid "$target_folder_uid" --arg rule_groups "$rule_groups" '.[] | select(.folderUID == $folder_uid and .ruleGroup != $rule_groups) | .uid'
}

delete_alert() {
	local grafana_url=${1}
	local sa_token=${2}
	local alert_uids_string=${3}

	while IFS= read -r alert_uid; do
		[[ -n "$alert_uid" ]] || continue
		curl -s -X DELETE "https://${grafana_url}/api/v1/provisioning/alert-rules/${alert_uid}" \
			-H "Authorization: Bearer ${sa_token}"
	done <<<"$alert_uids_string"
}

#================================================================
# Main
#================================================================
main() {
	read -rp "フォルダ名をスペース区切りで入力： " folder_names
	read -rp "削除しないruleGroup名を入力（全削除の場合はEnter）: " exclude_rule_groups

	for folder_name in $folder_names; do
		local folder_uid
		folder_uid=$(get_folder_uid "$GRAFANA_URL" "$SA_TOKEN" "$folder_name")
		echo "DEBUG: folder_uid=$folder_uid" >&2

		if [[ -z "$folder_uid" ]]; then
			echo "該当フォルダが見つかりません: $folder_name"
			exit 1
		fi

		local alert_uids
		alert_uids=$(get_alert_uids "$GRAFANA_URL" "$SA_TOKEN" "$folder_uid" "$exclude_rule_groups")
		echo -e "DEBUG: alert_uids=\n$alert_uids" >&2

		if [[ -z "$alert_uids" ]]; then
			echo "該当フォルダにアラートがありません: $folder_name"
			exit 0
		fi

		delete_alert "$GRAFANA_URL" "$SA_TOKEN" "$alert_uids"
		echo "アラート削除完了"
	done
}

main
