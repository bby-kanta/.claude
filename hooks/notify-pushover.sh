# https://zenn.dev/dely_jp/articles/0b78b2b1530878

#!/bin/bash
# CLAUDE_QUIET=1 を設定すると通知をスキップする（セッション単位で無効化したい場合に使用）
[ "${CLAUDE_QUIET}" = "1" ] && exit 0
PUSHOVER_USER_KEY="${PUSHOVER_USER_KEY:-YOUR_USER_KEY}"
PUSHOVER_API_TOKEN="${PUSHOVER_API_TOKEN:-YOUR_API_TOKEN}"

# stdin から hook の JSON を読み取る
INPUT=$(cat)
TITLE=$(echo "$INPUT" | jq -r '.title // "Claude Code"')
MESSAGE=$(echo "$INPUT" | jq -r '.message // "通知"')
DIR="${PWD#$HOME/}"
MESSAGE="📁 ${DIR}
${MESSAGE}"

curl -s \
  -F "token=${PUSHOVER_API_TOKEN}" \
  -F "user=${PUSHOVER_USER_KEY}" \
  -F "title=${TITLE}" \
  -F "message=${MESSAGE}" \
  -F "sound=pushover" \
  -F "priority=0" \
  https://api.pushover.net/1/messages.json > /dev/null 2>&1
