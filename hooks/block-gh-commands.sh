#!/bin/bash
# toolkit-reviewer用: ghコマンドを全てブロック（ローカル完結）
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ "$COMMAND" =~ ^gh[[:space:]] ]]; then
  echo "ブロック: このエージェントはローカル完結です。ghコマンドは使用できません: $COMMAND" >&2
  exit 2
fi

exit 0
