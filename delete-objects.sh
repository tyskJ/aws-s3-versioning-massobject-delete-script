#!/bin/bash

# 引数でバケット名を取得
if [[ -z "$1" ]]; then
  echo "Usage: $0 <bucket-name>"
  exit 1
fi

BUCKET_NAME="$1"

# 一時ファイルを作成
TMP_FILE=$(mktemp)

# オブジェクトのバージョンリストを取得
LIST_OUTPUT=$(aws s3api list-object-versions --bucket "$BUCKET_NAME")

# リスト取得の成功確認
if [[ $? -ne 0 ]]; then
  echo "Failed to retrieve object versions. Please check your bucket name and permissions."
  rm -f "$TMP_FILE"
  exit 1
fi

# プレフィックス（階層ごとにすべて）を抽出
echo "$LIST_OUTPUT" | jq -r '.Versions[].Key' | awk -F'/' '{
  prefix = "";
  for (i = 1; i < NF; i++) {
    prefix = (prefix ? prefix "/" : "") $i;
    print prefix "/";
  }
}' | sort | uniq > "$TMP_FILE"

# プレフィックスリストに "すべて削除" を追加
echo "Available prefixes:"
cat -n "$TMP_FILE"
echo "$(($(wc -l < "$TMP_FILE") + 1))) Delete all objects in the bucket"

# ユーザーに選択を求める
echo "Enter the number of the option to proceed:"
read -r OPTION_SELECTION

# ユーザーの選択を処理
if [[ -n "$OPTION_SELECTION" ]]; then
  TOTAL_OPTIONS=$(wc -l < "$TMP_FILE")
  if [[ "$OPTION_SELECTION" -eq "$((TOTAL_OPTIONS + 1))" ]]; then
    echo "You selected to delete all objects in the bucket."
    SELECTED_PREFIX=""
  else
    SELECTED_PREFIX=$(sed -n "${OPTION_SELECTION}p" "$TMP_FILE")
    if [[ -z "$SELECTED_PREFIX" ]]; then
      echo "Invalid selection. Exiting."
      rm -f "$TMP_FILE"
      exit 1
    fi
    echo "Selected prefix: $SELECTED_PREFIX"
  fi
else
  echo "No option selected. Exiting."
  rm -f "$TMP_FILE"
  exit 1
fi

# 削除対象オブジェクトリストの取得
if [[ -n "$SELECTED_PREFIX" ]]; then
  LIST_OUTPUT=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --prefix "$SELECTED_PREFIX")
fi

# jqでオブジェクトリストを安全に整形
echo "$LIST_OUTPUT" | jq -c '.Versions + .DeleteMarkers // [] | map({Key, VersionId})' > objects.json
TOTAL_OBJECTS=$(jq 'length' objects.json)

if [[ "$TOTAL_OBJECTS" -eq 0 ]]; then
  echo "No objects to delete in bucket '$BUCKET_NAME'."
  rm -f "$TMP_FILE" objects.json
  exit 0
fi

echo "Total objects to delete: $TOTAL_OBJECTS"

# APIのレスポンスがページングされて処理が止まらないようにする
export AWS_PAGER=""

# 1000件ずつ削除
BATCH_SIZE=1000
for ((i = 0; i < TOTAL_OBJECTS; i += BATCH_SIZE)); do
  END_INDEX=$((i + BATCH_SIZE))
  if [[ "$END_INDEX" -gt "$TOTAL_OBJECTS" ]]; then
    END_INDEX="$TOTAL_OBJECTS"
  fi

  jq --argjson start "$i" --argjson end "$END_INDEX" '.[$start:$end] | {Objects: .}' objects.json > batch.json
  aws s3api delete-objects --bucket "$BUCKET_NAME" --delete "file://batch.json"
  echo "Deleted objects $((i + 1)) to $END_INDEX"
done

# 一時ファイルを削除
rm -f "$TMP_FILE" objects.json batch.json

echo "Deletion completed for bucket '$BUCKET_NAME'."
