#!/bin/bash
# レビューエージェント用: 書き込み系コマンドをブロック
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

BLOCKED=(
  "(^|[&|;][[:space:]]*)git push"
  "(^|[&|;][[:space:]]*)git merge"
  "(^|[&|;][[:space:]]*)git rebase"
  "(^|[&|;][[:space:]]*)git reset"
  "(^|[&|;][[:space:]]*)git checkout -b"
  "(^|[&|;][[:space:]]*)gh pr merge"
  "(^|[&|;][[:space:]]*)gh pr close"
  "(^|[&|;][[:space:]]*)gh pr comment"
  "(^|[&|;][[:space:]]*)gh pr edit"
  "(^|[&|;][[:space:]]*)rm[[:space:]]"
  "(^|[&|;][[:space:]]*)mv[[:space:]]"
)

for pattern in "${BLOCKED[@]}"; do
  if [[ "$COMMAND" =~ $pattern ]]; then
    echo "ブロック: レビューエージェントでは書き込み操作は許可されていません: $COMMAND" >&2
    exit 2
  fi
done

exit 0
