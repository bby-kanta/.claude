---
name: autoresearch-controller
description: "autoresearch方式の自律ループでRailsコントローラーのパフォーマンスをチューニングするスキル。コード変更→ベンチマーク→keep/discardを繰り返し、レスポンスタイムを改善する。"
argument-hint: "[setup <Controller#action>] or [run]"
disable-model-invocation: true
---

# Autoresearch-Controller

[karpathy/autoresearch](https://github.com/karpathy/autoresearch) の自律研究ループの考え方をRailsコントローラーのパフォーマンスチューニングに応用したスキル。

## コンセプト

AIエージェントがコントローラーのコードを変更し、ベンチマークを実行し、改善したらkeep・悪化したらdiscardを**自律的に繰り返す**。人間はループを開始して放置し、戻ってきたら改善結果と試行履歴を確認する。

### 三つの原則

1. **固定された評価基準**: ベンチマークスクリプトとテストデータはAIが変更できない。公正な比較の土台
2. **テストデータの盲検化**: チューニングを行うエージェントはテストデータの中身を知ることができない。特定データへの過学習を防ぐ
3. **進化的選択圧**: 改善→keep（ブランチ進行）、悪化→discard（git reset）。常に最良の状態からスタート

## モード

- **`/autoresearch-controller setup <Controller#action>`** — 初回セットアップ。ブランチ作成、ベンチマーク生成、データ投入、ベースライン計測
- **`/loop 10m /autoresearch-controller run`** — 自律ループ実行（10分固定間隔）

### 時間予算

1サイクルの時間予算は **9分**。10分間隔のループの中で確実に完了させるため。
autoresearch が5分固定の訓練時間で全実験を公平に比較するように、このスキルも固定時間で各サイクルを比較する。
9分以内に完了しない場合は、変更を discard して即座に終了する。

---

## Setup フェーズ

`$ARGUMENTS` が `setup` で始まる場合、以下を実行する。

### 1. ターゲット確認

ユーザーから以下を聞き取る（引数で指定されていればそれを使う）:
- 対象アクション（例: `UsersController#index`）
- 対応するルート（例: `GET /api/users`）
- リクエストに必要なパラメータやヘッダー（あれば）
- 変更を許可するファイルの範囲（controller, model, service, migrationがデフォルトとしてユーザーに確認）

### 2. ブランチ作成

```bash
git checkout -b perf-tune/<controller>-<action>
```

mainブランチから分岐する。既にperf-tune/ブランチにいる場合はセットアップ済みの可能性があるので確認。

### 3. ベンチマークファイルの配置

プロジェクトに以下のファイルを生成する。テンプレートは `references/templates.md` を参照。

```
benchmark/
├── run.rb          ← ベンチマーク実行スクリプト
├── setup.rb        ← DB クリーン＋seed スクリプト
├── config.yml      ← 対象エンドポイント・計測設定
└── seed_data.rb    ← テストデータ定義（autoresearch-data-setup-agentのみで編集）
tuning_results.tsv  ← 試行履歴ログ（ヘッダー行のみで初期化）
```

**エージェントは事前定義済み**: `autoresearch-tuning-agent` と `autoresearch-data-setup-agent` は `~/.claude/agents/` に配置済み。セットアップ時に動的生成はしない。autoresearch-tuning-agent にはhooksで `benchmark/` 内データファイルの Read ブロックが組み込まれており、用意されたテストデータに絞った最適化を防ぐ。

**重要**: `seed_data.rb` のテストデータ定義は **autoresearch-data-setup-agent** を呼び出して作成する（autoresearch-tuning-agentにデータ内容を見せないため）。

### 4. テストデータの投入

事前定義済みの `autoresearch-data-setup-agent`（`~/.claude/agents/autoresearch-data-setup-agent.md`）をサブエージェントとして呼び出す。
このエージェントは `benchmark/*` 内ファイルへのフルアクセスを持つ。

**呼び出し時に渡すコンテキスト**:
- 対象の model ファイルパス
- db/schema.rb のパス
- benchmark/seed_data.rb のパス（ここにデータ定義を実装させる）
- 対象エンドポイントの説明（どういうデータが必要か）

#### autoresearch-data-setup-agent の役割
- 一番の役割は、`autoresearch-tuning-agent`にテストデータの内容をコンテキストに含ませないようにすること
- autoresearch-data-setup-agent が `seed_data.rb` を実装し、`RAILS_ENV=test ruby benchmark/setup.rb` でDBにデータを投入する。
- ユーザーに `seed_data.rb` の内容を確認してもらう。ユーザーがOKしたら次へ。
- データ数は大体1000レコード程度を目安に。関連レコードも十分に用意する。内容は現実的で多様性があることが望ましい。

### 5. ベースライン計測

```bash
RAILS_ENV=test ruby benchmark/run.rb
```

結果を `tuning_results.tsv` にベースラインとして記録:
```
commit	avg_ms	p95_ms	specs_passed	status	description
<hash>	245.3	312.1	true	baseline	初回ベースライン
```

### 6. セットアップ完了

ユーザーに以下を報告:
- ベースラインのレスポンスタイム
- 変更対象ファイルの一覧
- `/loop 10m /autoresearch-controller run` で自律ループを開始できること
- 1サイクルの時間予算は9分。10分間隔固定

---

## Cycle フェーズ（1サイクル = 1実験）

`$ARGUMENTS` が `run` の場合、以下を実行する。**必ず `/loop` 経由で呼び出されること。**
単体で `/autoresearch-controller run` が実行された場合は、ユーザーに `/loop Xm /autoresearch-controller run` での起動を案内して停止する。

### 前提チェック

1. `perf-tune/` ブランチにいることを確認（mainにいたら即abort）
2. `benchmark/config.yml` が存在することを確認（セットアップ済みか）

### autoresearch-tuning-agent の呼び出し

事前定義済みの `autoresearch-tuning-agent`（`~/.claude/agents/autoresearch-tuning-agent.md`）をサブエージェントとして呼び出す。
このエージェントにはhooksで benchmark/ 内ファイルの Read ブロックが組み込まれている。

**呼び出し時に渡すコンテキスト**:

以下の情報を収集し、`autoresearch-tuning-agent` へのプロンプトに含める:

1. **対象ファイル一覧**: `benchmark/config.yml` から対象エンドポイントを読み取り、対応する controller, model, service ファイルのパスを列挙
2. **関連specファイル一覧**: 対象ファイルに対応する spec ファイルのパスを列挙
3. **試行履歴**: `tuning_results.tsv` の全内容（過去の keep/discard/crash の記録）
4. **エンドポイント情報**: HTTPメソッド、パス、パラメータ
5. **現在のブランチ名とHEADコミットハッシュ**

**コンテキストの渡し方の例**:

```
以下のコンテキストで1サイクルのチューニングを実行してください。

## 対象
- エンドポイント: GET /api/users
- Controller: app/controllers/api/users_controller.rb
- Models: app/models/user.rb, app/models/post.rb
- Services: app/services/user_list_service.rb
- 関連spec: spec/controllers/api/users_controller_spec.rb, spec/models/user_spec.rb

## ブランチ
- 現在: perf-tune/users-index (HEAD: a1b2c3d)

## 試行履歴 (tuning_results.tsv)
commit	avg_ms	p95_ms	specs_passed	status	description
a1b2c3d	245.3	312.1	true	baseline	初回ベースライン
b2c3d4e	198.7	267.4	true	keep	eager loading追加
c3d4e5f	201.2	280.3	true	discard	サービスクラスにメモ化導入

## ルール
- キャッシュ導入は禁止（構造的改善が目的）
- Batch処理への逃しも禁止
- 1サイクル1変更。小さく保つ
- benchmark/ 内ファイルの読み取り・変更は禁止
```

autoresearch-tuning-agent は自身の定義に従い、以下を自律的に実行する:
1. コード分析 → 改善立案 → 実装 → コミット
2. migration があれば実行 + `RAILS_ENV=test ruby benchmark/setup.rb` で再seed
3. spec 実行 → 失敗なら revert
4. ベンチマーク実行
5. Keep or Discard 判定
6. tuning_results.tsv 更新

排他制御は不要。/loop の実行間隔がサイクルの重複を防ぐ。

---

## 安全機構

### ブランチ保護
- `perf-tune/` プレフィックスのブランチ以外では絶対に動作しない
- `main`・`develop`・`feature/*`ブランチにいる場合は即座に停止

### 変更範囲の制限
- 変更可能: controller, model, service class, migration
- 変更不可: benchmark/, spec/, config/, routes, Gemfile, .claude/

### テストデータ盲検化
- autoresearch-tuning-agent の Read hook が `benchmark/seed_data.rb`, `benchmark/setup.rb`, `benchmark/run.rb` への Read をブロック
- autoresearch-tuning-agent の Bash hook が `cat`, `head`, `grep` 等によるベンチマークファイルの間接閲覧をブロック
- ソフト制約として: テストデータの内容を推測・分析する試みも禁止
- エージェントが最適化すべきはコードの構造的パフォーマンスであり、特定データに対する最適化ではない

### Bash操作の制限（ホワイトリスト方式）

各エージェントの Bash hook はホワイトリスト方式。許可されたコマンドパターン以外は**全てブロック**される。

**autoresearch-tuning-agent のホワイトリスト** (`scripts/autoresearch-tuning-agent-guard-bash.sh`):
- `git add/commit/status/diff/log/branch --show-current/rev-parse`
- `git reset --hard HEAD~1`（1つ前の巻き戻しのみ）
- `bundle exec rspec <spec files>`
- `RAILS_ENV=test ruby benchmark/run.rb`
- `RAILS_ENV=test ruby benchmark/setup.rb`
- `RAILS_ENV=test bin/rails db:migrate / db:rollback`
- `grep/tail/head` on `run.log`（ベンチマーク出力の解析）
- `echo`, `cat tuning_results.tsv`, `wc`, `ls`

**autoresearch-data-setup-agent のホワイトリスト** (`scripts/autoresearch-data-setup-agent-guard-bash.sh`):
- `RAILS_ENV=test ruby benchmark/setup.rb`
- `RAILS_ENV=test bin/rails db:migrate / db:rollback`

**ホワイトリストの改善サイクル**:
エージェントが正当な操作でブロックされた場合、hookのエラーメッセージにブロックされたコマンドが表示されるので、ユーザーはこのコマンドを追加する判断をする。実運用を通じてホワイトリストを育てていく。

---

## 結果の確認

ユーザーがループを止めた後、`tuning_results.tsv` で全試行の履歴を確認できる。

```bash
cat tuning_results.tsv | column -t -s $'\t'
```

git log で各keepの変更内容を確認:
```bash
git log --oneline perf-tune/<name>
```

改善率の概算:
```
baseline avg_ms - best avg_ms = 改善量
(改善量 / baseline avg_ms) * 100 = 改善率%
```

---

## /loop での自律ループ実行手順

### 前提

- `/autoresearch-controller setup <Controller#action>` が完了していること
- `perf-tune/` ブランチにいること
- `benchmark/config.yml` と `tuning_results.tsv`（ベースライン記録済み）が存在すること

### Step 1: ループ開始

```
/loop 10m /autoresearch-controller run
```

ループ間隔は **10分固定**。各サイクルの時間予算は **9分**（1分のマージン）。
autoresearch が5分固定の訓練予算で全実験を比較するように、固定間隔によりサイクル間の公平性が保たれる。

これにより10分間隔で以下が繰り返される:
1. SKILL.md が起動し、前提チェック（ブランチ確認、config存在確認）
2. `benchmark/config.yml` と `tuning_results.tsv` を読み取り
3. autoresearch-tuning-agent をコンテキスト付きで呼び出し
4. autoresearch-tuning-agent が自律的に: コード変更 → commit → spec → ベンチマーク → keep/discard → 記録
5. サイクル完了。次の /loop 起動まで待機

### Step 3: 放置

ループが回っている間は放置してよい。autoresearch-tuning-agent は:
- hooks でベンチマークデータの閲覧が不可能
- ホワイトリスト方式の Bash guard で安全な操作のみ実行
- `perf-tune/` ブランチ上でのみ動作（main には影響しない）
- 各サイクルで keep/discard が判定され、常に最良の状態が維持される

### Step 4: 停止と確認

ループを止めたら（Ctrl+C or `/loop stop`）、結果を確認:

```bash
# 試行履歴の一覧
cat tuning_results.tsv | column -t -s $'\t'

# keepされた変更の一覧
git log --oneline

# 改善率の確認
# baseline と最新の avg_ms を比較
```

### Step 5: 成果の取り込み

チューニング結果に満足したら、通常のPRフローでmainに取り込む:

```bash
# perf-tune ブランチからPRを作成
gh pr create --title "perf: <Controller#action> のレスポンスタイム改善"
```

不要なら:

```bash
git checkout main
git branch -D perf-tune/<controller>-<action>
```

### 実行例（全体の流れ）

```
# 1. セットアップ（対話的）
> /autoresearch-controller setup UsersController#index

  → ブランチ作成、ベンチマーク生成、テストデータ投入、ベースライン計測
  → 「ベースライン: avg 245ms, p95 312ms」
  → 「/loop 10m /autoresearch-controller run で開始してください」

# 2. 自律ループ開始
> /loop 10m /autoresearch-controller run

  → 10分ごとに autoresearch-tuning-agent が1サイクル実行（9分以内に完了）
  → 寝る / 別の作業をする

# 3. 翌朝、結果確認
> cat tuning_results.tsv | column -t -s $'\t'

  commit   avg_ms  p95_ms  specs_passed  status   description
  a1b2c3d  245.3   312.1   true          baseline 初回ベースライン
  b2c3d4e  198.7   267.4   true          keep     eager loading追加
  c3d4e5f  201.2   280.3   true          discard  サービスクラスにメモ化
  d4e5f6g  0.0     0.0     false         crash    複合インデックス追加(migration error)
  e5f6g7h  182.4   241.8   true          keep     select限定 + 不要クエリ削除
  ...
  → baseline 245ms → best 182ms = 25.7% 改善
```
