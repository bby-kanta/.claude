---
name: anthropic-quad-review
description: code-review、pr-review-toolkit、codex review、codex adversarial-reviewの4つのレビューを同一PRに対して並列実行し、レビュー結果をreview-output/配下にエクスポートするスキル。
disable-model-invocation: true
---

# Anthropic Quad Review

Anthropic公式の code-review / pr-review-toolkit と、Codex の review / adversarial-review の計4つのレビューを同一PRに対して並列実行し、結果をファイルにエクスポートする。レビュープラグインの比較検証用。

## アーキテクチャ

```
メインエージェント（本スキル）
  │
  ├─ （必要に応じて）git worktree で PR ブランチを一時チェックアウト
  │
  ├─ anthropic-code-reviewer（読み取り専用サブエージェント）
  │   → レビュー結果をテキストで返す
  │
  ├─ anthropic-toolkit-reviewer（読み取り専用サブエージェント）
  │   → レビュー結果をテキストで返す
  │
  ├─ codex-reviewer（読み取り専用サブエージェント）
  │   → codex-companion.mjs review --scope branch を実行し結果を返す
  │
  ├─ codex-adversarial-reviewer（読み取り専用サブエージェント）
  │   → codex-companion.mjs adversarial-review --scope branch を実行し結果を返す
  │
  ← すべての結果を受け取る
  │
  ├─ メインエージェントがファイルに書き出す
  │
  └─ ワークツリーをクリーンアップ
```

4つのレビューサブエージェントはすべて `~/.claude/agents/` に定義済み。Write/Edit権限を持たず、読み取りとレビューのみ行う。

Codex系のエージェントは `codex-companion.mjs` を `--scope branch --wait` 付きで直接 Bash 実行する（Skill ツール経由ではない）。

ファイル書き出しはすべてメインエージェントが担当する。

## ワークフロー

### Step 1: PR情報の取得

引数でPR番号が指定されていればそれを使う。なければ現在のブランチから自動検出する。

```bash
gh pr view {PR番号} --json number,headRepository,headRefName
```

以下の3つを確定する:
- **リポジトリ名**: `headRepository.name`（取れなければ `gh repo view --json name` で取得）
- **PR番号**: `number`
- **PRブランチ名**: `headRefName`

いずれか取得できなければユーザーに確認する。

### Step 2: レビュー対象ブランチの準備

現在のブランチがPRのブランチと異なる場合、一時的なワークツリーを作成する。
これにより、ユーザーの作業ブランチを切り替えずにリモートPRをレビューできる。

```bash
current_branch=$(git branch --show-current)
```

**ケースA: `current_branch` == PRブランチ名の場合**
- ワークツリー不要
- `{worktree_path}` = 現在のリポジトリルート
- `{use_worktree}` = false

**ケースB: `current_branch` != PRブランチ名の場合**

以下を順番に実行する:

```bash
# 1. PRブランチをフェッチ
git fetch origin {PRブランチ名}

# 2. 既存の一時ワークツリー・ブランチがあれば削除
git worktree remove /tmp/quad-review-{PR番号} --force 2>/dev/null || true
git branch -D quad-review-{PR番号} 2>/dev/null || true

# 3. ワークツリーを作成（ローカルブランチ付き）
git worktree add -b quad-review-{PR番号} /tmp/quad-review-{PR番号} origin/{PRブランチ名}
```

- `{worktree_path}` = `/tmp/quad-review-{PR番号}`
- `{use_worktree}` = true

### Step 3: 出力ディレクトリの準備

```
/Users/kuboderakanta/.claude/skills/cross-reviewer-analysis/review-output/{リポジトリ名}/{PR番号}/
```

`mkdir -p` でディレクトリを作成する。

### Step 4: 4つのレビューを並列実行

Agent ツールで4つのサブエージェントを **同一ターンで同時に** 起動する。

**重要**: `{use_worktree}` が true の場合、各サブエージェントのプロンプトの **先頭** に以下のワークツリー指示を追加する。false の場合は追加しない:

```
**重要: ワークツリーでの作業ルール**

レビュー対象は {worktree_path} にある PR ブランチの clean checkout です。
メインリポジトリ（元の作業ディレクトリ）ではありません。

Claude Code の Bash ツールはシェル状態（cd を含む）が呼び出し間で保持されません。
以下のルールを厳守してください:

1. **Bash**: すべてのコマンドを `cd {worktree_path} && <コマンド>` の形式で単一の Bash 呼び出しとして実行すること。`cd` を単独で実行しても次の Bash 呼び出しには反映されません。
   - 例: `cd {worktree_path} && git diff main...HEAD`
   - 例: `cd {worktree_path} && git diff main...HEAD --name-only`
   - 例: `cd {worktree_path} && node /path/to/script.mjs review --wait --scope branch`

2. **Read / Grep / Glob**: ファイルパスは `{worktree_path}/` をベースにすること。メインリポジトリのパスを使わないこと。
   - 正: Read("{worktree_path}/app/models/user.rb")
   - 誤: Read("/Users/.../retail-api/.../user.rb")

3. **検証**: 最初の Bash 呼び出しで `cd {worktree_path} && git log --oneline -1` を実行し、PR ブランチにいることを確認すること。
```

#### エージェントA（Anthropic code-review）

- **subagent_type**: `anthropic-code-reviewer`
- **prompt**: `[ディレクトリ移動指示（該当時）] PR #{PR番号} を日本語でレビューしてください。レビュー結果の全文を最終レスポンスとして返してください。`
- **mode**: `plan`

#### エージェントB（Anthropic pr-review-toolkit）

- **subagent_type**: `anthropic-toolkit-reviewer`
- **prompt**: `[ディレクトリ移動指示（該当時）] 現在のブランチの変更を日本語でレビューしてください。レビュー結果の全文を最終レスポンスとして返してください。`
- **mode**: `plan`

#### エージェントC（Codex review）

- **subagent_type**: `codex-reviewer`
- **prompt**: 以下を連結して渡す:
  ```
  [ディレクトリ移動指示（該当時）]

  ブランチの変更をレビューしてください。

  最終レスポンスは以下の3セクションで構成してください:

  ## 実行証跡
  - 実行コマンド: （Bash で実行した node コマンドの全文）
  - 終了コード: （コマンドの exit code）
  - codex-companion.mjs の生出力（省略せずそのまま貼付）

  ## Codex ジョブログ
  レビュー完了後、Codex のジョブログを取得して貼付してください。
  ジョブの状態ディレクトリは $CLAUDE_PLUGIN_DATA/state/ 配下、
  またはフォールバック先の /tmp/codex-companion/ 配下にあります。
  以下の手順で取得:
  1. state ディレクトリ内の該当ワークスペースフォルダを ls で特定
  2. jobs/ ディレクトリ内の最新の .log ファイルの内容を貼付
  3. 同じ jobId の .json ファイルから status, threadId, turnId を抜粋

  ## レビュー結果
  codex-companion.mjs の生出力を日本語に翻訳したレビュー本文
  ```
- **mode**: `plan`

#### エージェントD（Codex adversarial-review）

- **subagent_type**: `codex-adversarial-reviewer`
- **prompt**: 以下を連結して渡す:
  ```
  [ディレクトリ移動指示（該当時）]

  ブランチの変更を批判的にレビューしてください。

  最終レスポンスは以下の3セクションで構成してください:

  ## 実行証跡
  - 実行コマンド: （Bash で実行した node コマンドの全文）
  - 終了コード: （コマンドの exit code）
  - codex-companion.mjs の生出力（省略せずそのまま貼付）

  ## Codex ジョブログ
  レビュー完了後、Codex のジョブログを取得して貼付してください。
  ジョブの状態ディレクトリは $CLAUDE_PLUGIN_DATA/state/ 配下、
  またはフォールバック先の /tmp/codex-companion/ 配下にあります。
  以下の手順で取得:
  1. state ディレクトリ内の該当ワークスペースフォルダを ls で特定
  2. jobs/ ディレクトリ内の最新の .log ファイルの内容を貼付
  3. 同じ jobId の .json ファイルから status, threadId, turnId を抜粋

  ## レビュー結果
  codex-companion.mjs の生出力を日本語に翻訳したレビュー本文
  ```
- **mode**: `plan`

### Step 5: 結果の書き出し

すべてのサブエージェントからレビュー結果を受け取ったら、メインエージェントが Write ツールで書き出す:

- エージェントAの結果 → `{output_dir}/code-review.md`
- エージェントBの結果 → `{output_dir}/pr-review-toolkit.md`
- エージェントCの結果 → `{output_dir}/codex-review.md`
- エージェントDの結果 → `{output_dir}/codex-adversarial-review.md`

Codex系（C, D）の出力ファイルには、サブエージェントが返した「実行証跡」セクションと「レビュー結果」セクションの両方をそのまま書き出す。実行証跡にはコマンド全文・終了コード・codex-companion.mjs の生出力が含まれるため、Codex経由で実行された証拠として機能する。

### Step 5.5: レビュー対象の検証

レビュー結果を書き出した後、PRの変更ファイル一覧と各レビュー結果で言及されているファイルを突合する。

```bash
gh pr view {PR番号} --json files --jq '.files[].path'
```

レビュー結果内で言及されているファイルがPRの変更ファイルと一致しない場合（例: PRの変更は `design_docs/recurring/` だがレビューが `REVIEW.md` に言及）、以下の警告を完了報告に含める:

```
⚠️ レビュー対象の不一致を検出:
- PRの変更ファイル: {PRの変更ファイル一覧}
- レビューで言及されたファイル: {レビュー内のファイル一覧}
ワークツリーへのディレクトリ移動が正しく行われなかった可能性があります。
```

### Step 6: ワークツリーのクリーンアップ

`{use_worktree}` が true の場合のみ実行する:

```bash
git worktree remove /tmp/quad-review-{PR番号} --force
git branch -D quad-review-{PR番号}
```

`{use_worktree}` が false の場合はスキップする。

### Step 7: 完了報告

```
## Quad Review 完了

- リポジトリ: {リポジトリ名}
- PR: #{PR番号}
- code-review: {output_dir}/code-review.md
- pr-review-toolkit: {output_dir}/pr-review-toolkit.md
- codex-review: {output_dir}/codex-review.md
- codex-adversarial-review: {output_dir}/codex-adversarial-review.md

差分分析を行うには `/cross-reviewer-analysis` を実行してください。
```