#!/bin/bash
# レビューエージェント用: 書き込み系コマンドをブロック
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

BLOCKED=(
  "^git push"
  "^git merge"
  "^git rebase"
  "^git reset"
  "^git checkout -b"
  "^gh pr merge"
  "^gh pr close"
  "^gh pr comment"
  "^gh pr edit"
  "^rm "
  "^mv "
)

for pattern in "${BLOCKED[@]}"; do
  if [[ "$COMMAND" =~ $pattern ]]; then
    echo "ブロック: レビューエージェントでは書き込み操作は許可されていません: $COMMAND" >&2
    exit 2
  fi
done

exit 0
