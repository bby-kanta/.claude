#!/bin/bash
#
# Controller Tuner - Benchmark File Read Blocker
# tuning-agent の PreToolUse (Read) hook として使用
#
# このスクリプトはReadツール呼び出し時に実行され、
# benchmark/ ディレクトリ内のデータファイルへのアクセスをブロックする。
#
# 環境変数:
#   TOOL_INPUT - Readツールに渡されたJSON入力（file_pathを含む）
#

# Readツールの入力からfile_pathを抽出
FILE_PATH=$(echo "$TOOL_INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')

# file_pathが空なら通過
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# ブロック対象のパターン
BLOCKED_PATTERNS=(
  "benchmark/seed_data"
  "benchmark/setup"
  "benchmark/run.rb"
)

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$FILE_PATH" | grep -q "$pattern"; then
    echo "BLOCKED: benchmark内部ファイルの読み取りは禁止されています: $FILE_PATH"
    echo "テストデータの盲検化を維持するため、このファイルの内容は閲覧できません。"
    echo "ベンチマークの実行は 'RAILS_ENV=test ruby benchmark/run.rb' で行ってください。"
    exit 2
  fi
done

# ブロック対象外なら通過
exit 0
