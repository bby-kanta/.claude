#!/bin/bash
# CLAUDE_QUIET=1 を設定すると通知をスキップする（セッション単位で無効化したい場合に使用）
[ "${CLAUDE_QUIET}" = "1" ] && exit 0
PUSHOVER_USER_KEY="${PUSHOVER_USER_KEY:-YOUR_USER_KEY}"
PUSHOVER_API_TOKEN="${PUSHOVER_API_TOKEN:-YOUR_API_TOKEN}"

# 引数: $1=title, $2=message, $3=sound, $4=priority
TITLE="${1:-Claude Code}"
MESSAGE="${2:-通知}"
SOUND="${3:-pushover}"
PRIORITY="${4:-0}"

curl -s \
  -F "token=${PUSHOVER_API_TOKEN}" \
  -F "user=${PUSHOVER_USER_KEY}" \
  -F "title=${TITLE}" \
  -F "message=${MESSAGE}" \
  -F "sound=${SOUND}" \
  -F "priority=${PRIORITY}" \
  https://api.pushover.net/1/messages.json > /dev/null 2>&1
