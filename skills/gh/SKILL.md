---
name: gh
description: CLIからGitHub操作が必要なときやghコマンドを使用するときに必要なスキル。GitHub CLI (gh) コマンドを実行する。PRの作成・確認・レビュー・マージ、issue管理、リポジトリ操作など。「PRを見て」「PR一覧」「issueを作成」「ghで確認して」などGitHub操作が必要なときに使用。
argument-hint: "[gh subcommand and args, e.g. 'pr list', 'pr view 123']"
---

# GitHub CLI (gh) コマンド実行スキル

## サンドボックス制約への対応

macOS環境ではClaude Codeのサンドボックスがキーチェーンへのアクセスをブロックするため、`gh`コマンドのTLS証明書検証が失敗する（`x509: OSStatus -26276`）。

これはセキュリティ上の問題ではなく、Go言語のHTTPクライアントがmacOS Security frameworkを通じて証明書を検証する際に、サンドボックスがキーチェーンファイルへのアクセスを制限していることが原因。

**全ての `gh` コマンド実行時に `dangerouslyDisableSandbox: true` を設定すること。**

## 実行方法

Bashツールで `gh` コマンドを実行する際、必ず以下のように設定する：

```
Bash(command: "gh ...", dangerouslyDisableSandbox: true)
```

## 使い方

`$ARGUMENTS` をそのまま `gh` コマンドの引数として渡す。

- `/gh pr list` — オープンなPR一覧
- `/gh pr view 123` — PR #123 の詳細
- `/gh pr diff 123` — PR #123 のdiff
- `/gh issue list` — issue一覧
- `/gh api repos/:owner/:repo/...` — GitHub API直接呼び出し

引数なしで呼ばれた場合は、`gh pr list` を実行してオープンなPR一覧を表示する。

認証が通ってない場合は、`gh auth login` を実行してGitHub CLIの認証を行う必要がある。

## 主要なレポジトリ
- delyjp
  - retail-api
    - レシチャレ・うさポ・クラシルリテールネットワーク事業（通称OW）のAPIサーバーのコードベース。
  - retail-api-serverside-architecture-review
    - retail-apiの仕様書やアーキテクチャのレビューを行うためのリポジトリ。
  - retail-terraform
    - retail-apiのインフラ構成のIaCコードを管理するリポジトリ。
  - kurashiru-coin-platform-api
    - コイン基盤のAPIサーバーのコードベース。
  - kurashiru-coin-platform-terraform
    - コイン基盤のインフラ構成のIaCコードを管理するリポジトリ。

## retail-apiレポジトリ

### 主要なワークフロー

実行したらGithubのURLをユーザーに渡して

#### ブランチを自動でdevブランチにマージして開発環境にデプロイする(retail-api)

```
gh workflow run deploy-asp-dev-trigger-auto-merge.yml \
  --repo delyjp/retail-api \
  --ref #{デプロイしたいブランチ名} \
```

#### devブランチを開発環境にデプロイする(retail-api)

```
gh workflow run deploy-dev-trigger.yml \
  --repo delyjp/retail-api \
  --ref #{dev-mmdd（本日の日付）} \
```

#### Batchの再実行
```
gh workflow run execute-batch-trigger.yml \                                                                                                              ─╯
  --repo delyjp/retail-api \
  --ref main \
  -f batch_class_name=〇〇Batch \
  -f environment=prd
```
