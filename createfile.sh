#!/bin/bash

# バケット名の入力チェック関数
function get_bucket_name {
    while true; do
        read -p "バケット名を入力してください: " BUCKET_NAME
        if [[ -n "$BUCKET_NAME" ]]; then
            # バケットの存在確認
            if aws s3 ls "s3://$BUCKET_NAME" > /dev/null 2>&1; then
                break
            else
                echo "エラー: バケット '$BUCKET_NAME' は存在しません。もう一度入力してください。"
            fi
        else
            echo "バケット名は空ではいけません。もう一度入力してください。"
        fi
    done
}

# ファイル数の入力チェック関数
function get_file_count {
    while true; do
        read -p "作成するファイル数を入力してください（正の整数）: " FILE_COUNT
        if [[ "$FILE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            echo "ファイル数は正の整数を入力してください。"
        fi
    done
}

# 入力を取得
get_bucket_name

read -p "プレフィックスを入力してください（省略可）: " PREFIX

# プレフィックスの整形
PREFIX="${PREFIX#/}"  # 先頭のスラッシュを削除
PREFIX="${PREFIX%/}"  # 末尾のスラッシュを削除

# プレフィックスが空でない場合のみスラッシュを追加
if [ -n "$PREFIX" ]; then
    PREFIX="${PREFIX}/"
fi

get_file_count

# ファイルを作成してアップロード
for ((i=1; i<=FILE_COUNT; i++)); do
    FILE_NAME="file_$i.txt"
    echo "This is file $i" > "$FILE_NAME"

    # ファイルを S3 にアップロード
    aws s3 cp "$FILE_NAME" "s3://$BUCKET_NAME/${PREFIX}${FILE_NAME}"

    # ローカルファイルを削除
    rm "$FILE_NAME"

    echo "ファイル $FILE_NAME を s3://$BUCKET_NAME/${PREFIX} にアップロードしました。"
done

echo "全てのファイルがアップロードされました。"
