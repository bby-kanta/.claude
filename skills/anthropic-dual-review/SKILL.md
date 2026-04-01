---
name: anthropic-dual-review
description: code-reviewとpr-review-toolkitを同一PRに対して並列実行し、レビュー結果をreview-output/配下にtxtエクスポートするスキル。
disable-model-invocation: true
---

# Anthropic Dual Review

code-review と pr-review-toolkit の2つのAnthropic公式レビュープラグインを同一PRに対して並列実行し、結果をファイルにエクスポートする。レビュープラグインの比較検証用。

## アーキテクチャ

```
メインエージェント（本スキル）
  │
  ├─ anthropic-code-reviewer（読み取り専用サブエージェント）
  │   → レビュー結果をテキストで返す
  │
  ├─ anthropic-toolkit-reviewer（読み取り専用サブエージェント）
  │   → レビュー結果をテキストで返す
  │
  ← 両方の結果を受け取る
  │
  └─ メインエージェントがファイルに書き出す
```

レビューサブエージェントは `~/.claude/agents/` に定義済み。Write/Edit権限を持たず、読み取りとレビューのみ行う。ファイル書き出しはメインエージェントが担当する。

## ワークフロー

### Step 1: PR情報の取得

引数でPR番号が指定されていればそれを使う。なければ現在のブランチから自動検出する。

```bash
gh pr view --json number,headRepository
```

以下の2つを確定する:
- **リポジトリ名**: `headRepository.name`（取れなければ `gh repo view --json name` で取得）
- **PR番号**: `number`

どちらか取得できなければユーザーに確認する。

### Step 2: 出力ディレクトリの準備

```
/Users/kuboderakanta/claude-review-plugin-diff/review-output/{リポジトリ名}/{PR番号}/
```

`mkdir -p` でディレクトリを作成する。

### Step 3: 2つのレビューを並列実行

Agent ツールで2つのサブエージェントを **同一ターンで同時に** 起動する。

#### エージェントA

- **subagent_type**: `anthropic-code-reviewer`
- **prompt**: `PR #{PR番号} を日本語でレビューしてください。レビュー結果の全文を最終レスポンスとして返してください。`
- **mode**: `plan`

#### エージェントB

- **subagent_type**: `anthropic-toolkit-reviewer`
- **prompt**: `現在のブランチの変更を日本語でレビューしてください。レビュー結果の全文を最終レスポンスとして返してください。`
- **mode**: `plan`
- **備考**: pr-review-toolkit は `git diff` で現在のブランチの差分を自動検出するため、PR番号の指定は不要

### Step 4: 結果の書き出し

両サブエージェントからレビュー結果を受け取ったら、メインエージェントが Write ツールで書き出す:

- エージェントAの結果 → `{output_dir}/code-review.md`
- エージェントBの結果 → `{output_dir}/pr-review-toolkit.md`

### Step 5: 完了報告

```
## Dual Review 完了

- リポジトリ: {リポジトリ名}
- PR: #{PR番号}
- code-review: {output_dir}/code-review.md
- pr-review-toolkit: {output_dir}/pr-review-toolkit.md

差分分析を行うには `/cross-reviewer-analysis` を実行してください。
```
