#!/bin/bash
#
# autoresearch-data-setup-agent Bash Guard Hook (ホワイトリスト方式)
# autoresearch-data-setup-agent の PreToolUse (Bash) hook として使用
#
# data-setup-agent に必要な最小限のBash操作のみ許可。
# && や ; でチェーンされたコマンドは各パートを個別にチェックする。
#
# 環境変数:
#   TOOL_INPUT - Bashツールに渡されたJSON入力（commandを含む）
#

# コマンド文字列を抽出
COMMAND=$(echo "$TOOL_INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')

if [ -z "$COMMAND" ]; then
  exit 0
fi

# =============================================================================
# ホワイトリスト定義
# =============================================================================

ALLOWED_PATTERNS=(
  # --- データ投入 ---
  '^\s*RAILS_ENV=test\s+ruby\s+benchmark/setup\.rb'          # DB seed 実行
  '^\s*RAILS_ENV=test\s+bin/rails\s+db:migrate'              # migration 実行
  '^\s*RAILS_ENV=test\s+bin/rails\s+db:rollback'             # migration rollback

  # --- データ検証 ---
  '^\s*RAILS_ENV=test\s+bundle\s+exec\s+rails\s+runner'      # rails runner（データ投入確認用）
)

# =============================================================================
# 単一コマンドの正規化関数
# =============================================================================
normalize_command() {
  local cmd="$1"
  cmd=$(echo "$cmd" | sed -E "s/^\s*docker\s+compose\s+exec\s+(-e\s+\S+\s+)*\S+\s+//")
  cmd=$(echo "$cmd" | sed -E "s/^\s*bash\s+-c\s+['\"]//; s/['\"](\s*$)/\1/")
  cmd=$(echo "$cmd" | sed -E "s/\s*<<\s*'?[A-Z]+'?.*//")
  cmd=$(echo "$cmd" | sed -E 's/\s*\|.*$//')
  cmd=$(echo "$cmd" | sed -E 's/\s*[0-9]*>&[0-9]+//g')
  cmd=$(echo "$cmd" | sed -E 's/\s*$//')
  echo "$cmd"
}

# =============================================================================
# ホワイトリスト照合関数
# =============================================================================
check_whitelist() {
  local normalized="$1"
  for pattern in "${ALLOWED_PATTERNS[@]}"; do
    if echo "$normalized" | grep -qE "$pattern"; then
      return 0
    fi
  done
  return 1
}

# =============================================================================
# メイン: && / ; / || で分割し各パートを個別チェック
# =============================================================================

IFS=$'\n' read -r -d '' -a PARTS < <(echo "$COMMAND" | sed 's/\s*&&\s*/\n/g; s/\s*;\s*/\n/g; s/\s*||\s*/\n/g' && printf '\0')

BLOCKED_PART=""
for part in "${PARTS[@]}"; do
  [ -z "$part" ] && continue
  normalized=$(normalize_command "$part")
  [ -z "$normalized" ] && continue
  if ! check_whitelist "$normalized"; then
    BLOCKED_PART="$part"
    break
  fi
done

if [ -n "$BLOCKED_PART" ]; then
  blocked_normalized=$(normalize_command "$BLOCKED_PART")
  echo "BLOCKED: このコマンドは autoresearch-data-setup-agent のホワイトリストに含まれていません。"
  echo "ブロックされたパート: $BLOCKED_PART"
  echo "正規化後: $blocked_normalized"
  echo ""
  echo "許可されているコマンド:"
  echo "  - RAILS_ENV=test ruby benchmark/setup.rb"
  echo "  - RAILS_ENV=test bin/rails db:migrate / db:rollback"
  echo "  - RAILS_ENV=test bundle exec rails runner ..."
  echo ""
  echo "このコマンドが必要な場合は、autoresearch-data-setup-agent-guard-bash.sh のホワイトリストに追加してください。"
  exit 2
fi

exit 0
