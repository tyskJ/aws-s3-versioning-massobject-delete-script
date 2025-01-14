#!/bin/bash

# 引数でバケット名を取得
if [[ -z "$1" ]]; then
  echo "Usage: $0 <bucket-name>"
  exit 1
fi

BUCKET_NAME="$1"

# 一時ファイルを作成
TMP_FILE=$(mktemp)

# オブジェクトのリストを取得
LIST_OUTPUT=$(aws s3api list-object-versions --bucket "$BUCKET_NAME")

# リスト取得の成功確認
if [[ $? -ne 0 ]]; then
  echo "Failed to retrieve object versions. Please check your bucket name and permissions."
  rm -f "$TMP_FILE"
  exit 1
fi

# jq で Versions フィールドを安全に抽出（null の場合は空配列を代入）
echo "$LIST_OUTPUT" | jq '.Versions + .DeleteMarkers // [] | map({Key, VersionId})' > "$TMP_FILE"

# 総オブジェクト数を確認
TOTAL_OBJECTS=$(jq 'length' "$TMP_FILE")
echo "Total objects in bucket '$BUCKET_NAME': $TOTAL_OBJECTS"

if [[ "$TOTAL_OBJECTS" -eq 0 ]]; then
  echo "No objects to delete in bucket '$BUCKET_NAME'."
  rm -f "$TMP_FILE"
  exit 0
fi

# APIのレスポンスがページングされて処理が止まらないようにする
export AWS_PAGER=""

# 1000件ずつ分割して削除
BATCH_SIZE=1000
for ((i = 0; i < TOTAL_OBJECTS; i += BATCH_SIZE)); do
  echo "Deleting objects $((i + 1)) to $((i + BATCH_SIZE))..."
  
  # 1000件以下でも対応可能: 現在のバッチの終了位置を計算
  END_INDEX=$((i + BATCH_SIZE))
  if [[ "$END_INDEX" -gt "$TOTAL_OBJECTS" ]]; then
    END_INDEX="$TOTAL_OBJECTS"
  fi
  
  # バッチのオブジェクトを抽出
  jq --argjson start "$i" --argjson end "$END_INDEX" '.[$start:$end] | {Objects: .}' "$TMP_FILE" > batch.json
  
  # 削除コマンドを実行
  aws s3api delete-objects --bucket "$BUCKET_NAME" --delete "file://batch.json"
  
  # 削除結果を表示
  echo "Deleted objects $((i + 1)) to $END_INDEX"
done

# 一時ファイルを削除
rm -f "$TMP_FILE" batch.json

echo "Deletion completed for bucket '$BUCKET_NAME'."
