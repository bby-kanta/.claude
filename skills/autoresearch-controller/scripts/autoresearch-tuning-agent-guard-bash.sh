#!/bin/bash
#
# autoresearch-tuning-agent Bash Guard Hook (ホワイトリスト方式)
# autoresearch-tuning-agent の PreToolUse (Bash) hook として使用
#
# 許可されたコマンドパターンのみ実行可能。それ以外は全てブロック。
# && や ; でチェーンされたコマンドは各パートを個別にチェックする。
# 1つでも許可されていないパートがあれば全体をブロック。
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
  # --- Git（安全な操作のみ）---
  '^\s*git\s+add\s'                          # git add <files>
  '^\s*git\s+commit\s'                       # git commit -m "..."
  '^\s*git\s+reset\s+--hard\s+HEAD~1\s*$'   # git reset --hard HEAD~1（1つ前のみ）
  '^\s*git\s+status'                         # git status
  '^\s*git\s+diff'                           # git diff
  '^\s*git\s+log'                            # git log
  '^\s*git\s+branch\s+--show-current'        # git branch --show-current
  '^\s*git\s+rev-parse'                      # git rev-parse HEAD 等
  '^\s*git\s+stash'                           # git stash / git stash pop 等

  # --- spec 実行 ---
  '^\s*(RAILS_ENV=test\s+)?bundle\s+exec\s+rspec\s'  # bundle exec rspec <spec files>

  # --- ベンチマーク・Rails コマンド ---
  '^\s*RAILS_ENV=test\s+ruby\s+benchmark/run\.rb'     # ベンチマーク実行
  '^\s*RAILS_ENV=test\s+ruby\s+benchmark/setup\.rb'   # データ再seed
  '^\s*RAILS_ENV=test\s+bin/rails\s+db:migrate'       # migration 実行
  '^\s*RAILS_ENV=test\s+bin/rails\s+db:rollback'      # migration rollback

  # --- ベンチマーク結果の解析（出力のgrep）---
  '^\s*grep\s+.*\s+run\.log'                 # grep "^avg_ms:" run.log 等
  '^\s*tail\s+.*\s+run\.log'                 # tail -n 50 run.log（エラー確認用）
  '^\s*head\s+.*\s+run\.log'                 # head run.log

  # --- tuning_results.tsv 操作 ---
  '^\s*echo\s+.*>>\s*tuning_results\.tsv'    # echo "..." >> tuning_results.tsv（追記）
  '^\s*cat\s+tuning_results\.tsv'            # cat tuning_results.tsv（読み取り）

  # --- 基本ユーティリティ ---
  '^\s*echo\s'                               # echo（出力用）
  '^\s*wc\s'                                 # wc（行数カウント等）
  '^\s*ls\s'                                 # ls（ファイル一覧）
)

# =============================================================================
# 単一コマンドの正規化関数
# docker compose exec / bash -c / ヒアドキュメント / パイプ を除去して
# 実際のコマンド部分だけを返す
# =============================================================================
normalize_command() {
  local cmd="$1"

  # docker compose exec を除去
  cmd=$(echo "$cmd" | sed -E "s/^\s*docker\s+compose\s+exec\s+(-e\s+\S+\s+)*\S+\s+//")

  # bash -c '...' / bash -c "..." ラッパーを除去
  cmd=$(echo "$cmd" | sed -E "s/^\s*bash\s+-c\s+['\"]//; s/['\"](\s*$)/\1/")

  # ヒアドキュメントリダイレクト (<< 'RUBY' 等) を除去
  cmd=$(echo "$cmd" | sed -E "s/\s*<<\s*'?[A-Z]+'?.*//")

  # パイプ以降を除去
  cmd=$(echo "$cmd" | sed -E 's/\s*\|.*$//')

  # リダイレクト (2>&1 等) を除去
  cmd=$(echo "$cmd" | sed -E 's/\s*[0-9]*>&[0-9]+//g')

  # 末尾の空白を除去
  cmd=$(echo "$cmd" | sed -E 's/\s*$//')

  echo "$cmd"
}

# =============================================================================
# ホワイトリスト照合関数
# 正規化後のコマンドがいずれかのパターンにマッチすれば 0 を返す
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
# メイン: && / ; でコマンドを分割し、各パートを個別チェック
# 全パートが許可されていれば通過。1つでもNGなら全体をブロック
# =============================================================================

# && と ; で分割（|| も含む）
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
  echo "BLOCKED: このコマンドは autoresearch-tuning-agent のホワイトリストに含まれていません。"
  echo "ブロックされたパート: $BLOCKED_PART"
  echo "正規化後: $blocked_normalized"
  echo ""
  echo "許可されているコマンド:"
  echo "  - git add/commit/status/diff/log/reset --hard HEAD~1"
  echo "  - bundle exec rspec <spec files>"
  echo "  - RAILS_ENV=test ruby benchmark/run.rb"
  echo "  - RAILS_ENV=test ruby benchmark/setup.rb"
  echo "  - RAILS_ENV=test bin/rails db:migrate / db:rollback"
  echo "  - grep/tail/head on run.log"
  echo "  - echo, cat tuning_results.tsv, wc, ls"
  echo ""
  echo "このコマンドが必要な場合は、autoresearch-tuning-agent-guard-bash.sh のホワイトリストに追加してください。"
  exit 2
fi

# 全パート許可
exit 0
