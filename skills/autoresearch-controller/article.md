# はじめに

こんにちは、AIにレビューを任せてたらいつしか自分がレビュー対象になっていました。たろう眼鏡です。

Karpathy氏が公開した [autoresearch](https://github.com/karpathy/autoresearch) をご存知でしょうか。AIエージェントにLLMの訓練コードを渡して放置すると、勝手にモデルを改善し続けてくれるというリポジトリです。

これを見たとき、「この仕組み、サーバーサイドのパフォーマンスチューニングにも使えるのでは？」と思いました。コントローラーが遅い → コードを直す → ベンチマークを取る → 良くなったら採用、ダメなら戻す。これは日常的にやっている作業ですが、1塁ベースに全力でヘッドスライディングするような泥臭いものです。

1塁にヘッドスライディングするのはAIに任せて10分ごとに自動で回させたら、寝ている間に数十回の改善サイクルが走ります。ただし、AIに自律的にコードを触らせるには「暴走しない仕組み」が必要です。そこで、autoresearchの設計思想を借りつつ、Claude Codeのhooksやサブエージェントを使った防御機構を組み合わせて、安全に自律チューニングを回す仕組みを作りました。

この記事では、autoresearchの概念を軽く紹介した上で、それをどうサーバーサイドに転用したか、そしてAIを安全に自律動作させるため、私なりのハーネスエンジニアリングについて解説します。

---

# autoresearch とは何か

2026年3月、Karpathy氏が [autoresearch](https://github.com/karpathy/autoresearch)を公開しました。公開3週間で60,000スターを獲得したこのリポジトリの中身はシンプルです。

**AIエージェントに小さなLLMの訓練コードを渡し、「改善して」と指示して放置します。** エージェントはコードを変更し、5分間訓練し、結果を見て、良くなったらkeep、悪くなったらdiscardします。これを永遠に繰り返します。人間が寝ている間に約100回の実験が自動で行われ、朝起きたらモデルが改善されています。

```text
LOOP FOREVER:
  1. コードを変更
  2. 5分間訓練
  3. val_bpb を計測
  4. 改善 → keep（ブランチを進める）
  5. 悪化 → discard（git reset）
  6. 1に戻る
```

このシンプルなループが機能する理由は、3つの設計原則にあります。

## 原則1: 固定された評価基準

アウトプットに対する評価関数が固定されており、AIは変更できません。どんなにアーキテクチャを変えても、同じ基準で公平に比較されます。

## 原則2: 固定された時間予算

訓練は常に5分です。この制約があるから、モデルサイズを変えても、バッチサイズを変えても、結果が直接比較可能になります。
また、制約があるので最小限の変更が選ばれやすくなります。小さな変更で少しずつ改善していくスタイルが自然に促されます。

## 原則3: 進化的選択圧

改善したら keep、悪化したら discard。常に最良の状態からスタートします。

この構造は生物の進化に似ています。現在の最良個体（コード）に変異（変更）を加え、より良ければ生き残り、悪ければ淘汰される。進化的アルゴリズムとの違いは、変異がランダムではないことです。AIは過去の試行履歴を読み、「何が効いて何がダメだったか」を理解した上で次の変更を考えます。ランダムな突然変異ではなく、知識に裏打ちされた仮説検証を繰り返しているわけです。

---

# サーバーサイドのパフォーマンスチューニングに転用する

`autoresearch`のループは、LLM訓練に限った話ではないと考えました。
「コードを変更 → 計測 → 判定 → 記録」というPDCAサイクルが回せる問題であれば、同じ構造が適用できます。

今回、これを **Railsコントローラーのレスポンスタイム改善** に適用しました。

| autoresearch | autoresearch-controller |
|---|---|
| `train.py` を変更 | controller / model / service を変更 |
| val_bpb で評価 | 平均レスポンスタイム (avg_ms) で評価 |
| 5分間の訓練 | 10分間のサイクル（分析→実装→テスト→計測） |
| `prepare.py` が固定 | `benchmark/run.rb` が固定 |
| `program.md` が指示 | `SKILL.md` + サブエージェント定義が指示 |

## なぜこれが必要だったか

パフォーマンスチューニングは、仮説を立て、コードを変え、検証し、結果を見て次を考える、という泥臭い改善サイクルの繰り返しです。1回のサイクルにエンジニアが30分〜1時間かけていたものを、AIに10分間隔で自律的に回させます。人が8時間寝ている間に最大48回の実験を行うことも可能です。

ただし、パフォーマンスチューニングをAIに自律的に任せるには、多くの**防御機構**が必要になります。
例えば、寝ている間にAIが「DBにDROP TABLEするコードを書いて実行する」なんてことが起きないようにする必要があるので後述します。

## ノンゴール
- 今回Railsでやりましたが、他のサーバーサイド言語やフレームワークでも同様の構造が適用可能です
  - よってRuby・Rails固有のロジックや実装に関するロジックはこの記事では省きます
- パフォーマンスチューニングの具体的なテクニックや、どんなコード変更が効果的だったか、なども今回はノンゴールとします
  - 重要なのは、Claude Codeによって自律的なPDCAサイクルを回させる仕組みの設計と実装です
- 既にautoresearchに関するSKILLSなどが世間にはありますが、それらを本記事では使いません。自身の勉強も兼ねて、ゼロベースから設計・実装しています
- 並列化して複数のサイクルを同時に回すことは複雑になるのでノンゴールとします

---

# アーキテクチャ全体像

```mermaid
graph TD
    User["ユーザー"]
    Setup["/autoresearch-controller setup HogeController#index<br/>DB・計測ロジックセットアップ"]
    Loop["/loop 10m /autoresearch-controller run<br/>10分ごとに自動起動"]
    Skill["SKILL.md（オーケストレーター）<br/>コンテキスト収集 → エージェント呼び出し"]
    Tuning["autoresearch-tuning-agent<br/>・コード分析<br/>・改善実装<br/>・テスト実行<br/>・ベンチマーク<br/>・keep / discard<br/>"]
    DataSetup["autoresearch-data-setup-agent<br/>・テストデータ定義<br/>・DB seed<br/>"]

    User --> Setup
    Setup --> Loop
    Loop --> Skill
    Skill --> Tuning
    Skill --> DataSetup
```

ファイル構成:

```
~/.claude/skills/autoresearch-controller/
├── SKILL.md (オーケストレーション定義)
├── references/templates.md (必要ファイルのテンプレート)
└── scripts/
    ├── autoresearch-tuning-agent-block-read.sh     (データ定義を読むのをブロックするhooks)
    ├── autoresearch-tuning-agent-guard-bash.sh     (Bashのホワイトリストhooks)
    └── autoresearch-data-setup-agent-guard-bash.sh (Bashのホワイトリストhooks)

~/.claude/agents/ ← サブエージェント定義
├── autoresearch-tuning-agent.md
└── autoresearch-data-setup-agent.md

<Rails側のプロジェクト>/ ← セットアップ時に生成
├── benchmark/
│   ├── run.rb          ← ベンチマーク実行（AI変更不可）
│   ├── setup.rb        ← DBクリーン＋seed（AI変更不可）
│   ├── config.yml      ← 計測設定（AIが読める唯一のベンチマーク設定）
│   └── seed_data.rb    ← テストデータ定義（data-setup-agentのみ編集可）
└── tuning_results.tsv  ← 試行履歴ログ（これをAIが参照して次の改善案を立案）
```

---

# SKILL.md ── 自律ループの設計図

SKILL.md はClaude Codeのスキル機能で、AIの行動パターンを定義するMarkdownファイルです。`autoresearch`における `program.md` に相当します。

2つのモードを持っています:

- **setup**: 初回のセットアップ（ブランチ作成、ベンチマーク生成、テストデータ投入、ベースライン計測）
- **run**: 1サイクルの実験。基本的には`/loop`コマンドで10分ごとに繰り返し起動することを想定します。

以下が実際のSKILL.mdの全文です:

```markdown
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
2. **テストデータの隔離**: チューニングを行うエージェントはテストデータの中身を知ることができない。特定データへの過学習を防ぐ
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

git checkout -b perf-tune/<controller>-<action>

mainブランチから分岐する。既にperf-tune/ブランチにいる場合はセットアップ済みの可能性があるので確認。

### 3. ベンチマークファイルの配置

プロジェクトに以下のファイルを生成する。テンプレートは `references/templates.md` を参照。

benchmark/
├── run.rb          ← ベンチマーク実行スクリプト
├── setup.rb        ← DB クリーン＋seed スクリプト
├── config.yml      ← 対象エンドポイント・計測設定
└── seed_data.rb    ← テストデータ定義（autoresearch-data-setup-agentのみで編集）
tuning_results.tsv  ← 試行履歴ログ（ヘッダー行のみで初期化）

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

RAILS_ENV=test ruby benchmark/run.rb

結果を `tuning_results.tsv` にベースラインとして記録:

commit	avg_ms	p95_ms	specs_passed	status	description
<hash>	245.3	312.1	true	baseline	初回ベースライン

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

autoresearch-tuning-agent は自身の定義に従い、以下を自律的に実行する:
1. コード分析 → 改善立案 → 実装 → コミット
2. migration があれば実行 + `RAILS_ENV=test ruby benchmark/setup.rb` で再seed
3. spec 実行 → 失敗なら revert
4. ベンチマーク実行
5. Keep or Discard 判定
6. tuning_results.tsv 更新

---

## 安全機構

### ブランチ保護
- `perf-tune/` プレフィックスのブランチ以外では絶対に動作しない
- `main`・`develop`・`feature/*`ブランチにいる場合は即座に停止

### 変更範囲の制限
- 変更可能: controller, model, service class, migration
- 変更不可: benchmark/, spec/, config/, routes, Gemfile, .claude/

### テストデータ隔離
- autoresearch-tuning-agent の Read hook が `benchmark/seed_data.rb`, `benchmark/setup.rb`, `benchmark/run.rb` への Read をブロック
- autoresearch-tuning-agent の Bash hook が `cat`, `head`, `grep` 等によるベンチマークファイルの間接閲覧をブロック
- ソフト制約として: テストデータの内容を推測・分析する試みも禁止
- エージェントが最適化すべきはコードの構造的パフォーマンスであり、特定データに対する最適化ではない

### Bash操作の制限（ホワイトリスト方式）

各エージェントの Bash hook はホワイトリスト方式。許可されたコマンドパターン以外は**全てブロック**される。
```

### 固定間隔の設計意図

autoresearch が5分の訓練時間を固定しているのは、異なるアーキテクチャの実験を公平に比較するためです。同様に、今回は10分間隔を固定しました。

これにより:
- サイクル間の公平性が保たれます
- 小さい変更を選ぶ圧力が自然に生まれます

# templates.md
ここはプロジェクトやプログラミング言語により異なるので深く理解する必要はないです。
ベンチマークの取り方とテストデータが用意できれば何でも良いです。

````md
# autoresearch-controller テンプレート

セットアップフェーズで以下のファイルをプロジェクトに生成する。
`{{VARIABLE}}` はセットアップ時にユーザー入力で置換する。

## benchmark/config.yml

```yaml
# Controller Tuner ベンチマーク設定
# このファイルはtuning-agentが読める唯一のベンチマーク設定ファイル
endpoint: "{{ENDPOINT}}"        # 例: /api/users
method: "{{HTTP_METHOD}}"       # 例: GET
iterations: 20                  # 計測回数
warmup: 3                       # ウォームアップ回数（計測から除外）
params: {{PARAMS_HASH}}         # 例: { page: 1, per_page: 20 }
headers:
  Accept: "application/json"
# 認証が必要な場合はここに追加（seed_data.rb で同じトークンを使う）
# Authorization: "Bearer benchmark_fixed_access_token"
# Platform: "ios"
```

## benchmark/run.rb

```ruby
# frozen_string_literal: true
#
# Controller Tuner ベンチマークランナー
# !! このファイルはAIエージェントによる読み取り・変更が禁止されています !!
#
require_relative "../config/environment"
require "benchmark"
require "yaml"

config = YAML.load_file(File.join(__dir__, "config.yml"))

endpoint   = config["endpoint"]
method     = (config["method"] || "GET").downcase.to_sym
iterations = config["iterations"] || 20
warmup     = config["warmup"] || 3
params     = config["params"] || {}
headers    = config["headers"] || {}

# テストデータのセットアップ（毎回クリーン＋再seed）
load File.join(__dir__, "setup.rb")

app = ActionDispatch::Integration::Session.new(Rails.application)

# ウォームアップ（計測から除外）
warmup.times do
  app.send(method, endpoint, params: params, headers: headers)
end

# 本計測
times = []
iterations.times do
  # 各リクエスト前にDBコネクションプールをクリア
  ActiveRecord::Base.connection_pool.release_connection

  result = Benchmark.measure do
    app.send(method, endpoint, params: params, headers: headers)
  end
  times << (result.real * 1000) # ミリ秒に変換
end

# 最後のレスポンスステータスを確認
status = app.response.status

# 統計計算
times.sort!
avg_ms = times.sum / times.size
p50_ms = times[times.size / 2]
p95_ms = times[(times.size * 0.95).floor]
min_ms = times.first
max_ms = times.last

# 結果出力（この形式は固定。tuning-agentがgrepで読み取る）
puts "---"
puts "avg_ms:     #{avg_ms.round(1)}"
puts "p50_ms:     #{p50_ms.round(1)}"
puts "p95_ms:     #{p95_ms.round(1)}"
puts "min_ms:     #{min_ms.round(1)}"
puts "max_ms:     #{max_ms.round(1)}"
puts "iterations: #{iterations}"
puts "status:     #{status}"
```

## benchmark/setup.rb

```ruby
# frozen_string_literal: true
#
# Controller Tuner DB セットアップ
# !! このファイルはAIエージェントによる読み取り・変更が禁止されています !!
# テストDBをクリーンにし、ベンチマーク用データを投入する
#

# こちらにプロジェクト固有のロジックを書く
```

---

## benchmark/seed_data.rb

```ruby
# frozen_string_literal: true
#
# ベンチマーク用テストデータ定義
# !! このファイルはtuning-agentによる読み取りが禁止されています !!
# !! data-setup-agentのみが読み取り・編集できます !!
#
# data-setup-agent がセットアップ時にこのファイルを生成します。
# テストデータの内容はチューニングの公正性のため、tuning-agentから隠蔽されます。
#

# こちらにプロジェクト固有のロジックを書く
```

---

## tuning_results.tsv（初期状態）

```
commit	avg_ms	p95_ms	specs_passed	status	description
```

ヘッダー行のみ。タブ区切り（TSV）。カンマは description 内で使えるようにTSVを採用。
````

# サブエージェント ── テストデータの隔離

## なぜ隔離が必要か

AIがテストデータの中身を知っていると、そのデータに特化した最適化をしてしまう可能性があります。例えば「ユーザーが100人しかいない」と知れば、100人前提のハードコードなどで最適化ができます。これは本番環境相当のデータでは効果が出ません。

autoresearchと同じ構造を実現するために、エージェントを2つに分離しました。

## autoresearch-tuning-agent（チューニング実行）

コードの分析・改善・テスト・ベンチマーク・判定を行う中核となるサブエージェントです。**ベンチマークのデータファイルは一切読めません**。

```markdown
---
name: autoresearch-tuning-agent
description: autoresearch-controller スキル専用。benchmark/内データファイルの Read は
  hooks でブロック、Bash はホワイトリスト方式で制限。
tools: Read, Edit, Bash, Glob, Grep, Write
model: opus
hooks:
  PreToolUse:
    - matcher: "Read"
      hooks:
        - type: command
          command: "$HOME/.claude/skills/autoresearch-controller/scripts/autoresearch-tuning-agent-block-read.sh"
    - matcher: "Bash"
      hooks:
        - type: command
          command: "$HOME/.claude/skills/autoresearch-controller/scripts/autoresearch-tuning-agent-guard-bash.sh"
---

# Autoresearch Tuning Agent

## 絶対的な制約

### 読み取り禁止（hooks で強制 + ソフト制約）
- benchmark/seed_data.rb — テストデータの定義。内容を知ってはならない
- benchmark/setup.rb — DB seedスクリプト。内容を知ってはならない
- benchmark/run.rb — ベンチマーク実行スクリプト。内容を知ってはならない
- あなたが最適化すべきはコードの**構造的パフォーマンス**であり、特定データに対する最適化ではない

### 時間予算: 9分

1サイクルは 9分以内 に完了すること。
9分を超えそうな場合は、その時点で変更を discard して即座に終了する。
迷ったら小さい変更を選ぶ。

### 手順

1. 状況把握: 渡された試行履歴を分析。何が効いて何がダメだったか
2. コード分析: 対象のcontroller/model/serviceを読み、改善案を立案
3. 実装: コードを変更
4. コミット
5. spec実行 → 失敗なら修正試行（最大3回）→ ダメなら revert
6. ベンチマーク実行
7. 判定: avg_ms が前回keepより低い AND spec全パス → keep / それ以外 → discard
8. 記録: tuning_results.tsv に結果を追記

### 改善方針

- キャッシュの導入は禁止（構造的な改善が目的）
- Batch処理への逃しも禁止（同期的なロジック改善が目的）
- 1サイクルの変更は小さく保つ。複数の改善を一度に入れない
- コードの簡潔性を重視。複雑な変更で微小な改善なら不採用
```

### hooksによる制御
ポイントは、frontmatter の `hooks` セクションです。Claude Code のサブエージェントは個別のhooksを持つことができ、Read ツールと Bash ツールにそれぞれ制御スクリプトが紐づいています。

## autoresearch-data-setup-agent（データ準備）

テストデータの定義とDBセットアップを担当するエージェントです。benchmark/ ディレクトリへのフルアクセスを持ちますが、Bashは最小限に制限されています。
複雑な処理ではないのでコスパを重視してモデルは`sonnet`を指定しています。

```markdown
---
name: autoresearch-data-setup-agent
description: autoresearch-controller スキル専用。ベンチマーク用テストデータの定義とDBセットアップを行う。benchmark/内ファイルへのフルアクセスあり。Bash はホワイトリスト方式で制限。
tools: Read, Write, Edit, Bash, Glob, Grep
model: sonnet
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "$HOME/.claude/skills/autoresearch-controller/scripts/autoresearch-data-setup-agent-guard-bash.sh"
---

# Autoresearch Data Setup Agent

autoresearch-controller スキルのデータ準備エージェント。
tuning-agent がテストデータの内容を知らない状態でチューニングできるよう、データ定義とDB投入を分離して担当する。

呼び出し時に渡されるコンテキスト（対象model、スキーマ情報など）に従って動作する。

## 役割

1. 対象の controller/model の構造を分析し、現実的なテストデータを設計する
2. `benchmark/seed_data.rb` にデータ生成ロジックを実装する
3. `RAILS_ENV=test ruby benchmark/setup.rb` を実行してテストDBにデータを投入する

## テストデータ設計の指針

- **現実的なデータ量**: 本番環境に近いレコード数を用意する。少なすぎるとN+1等のパフォーマンス問題が顕在化しない
- **関連レコード**: has_many 関連があれば、関連レコードも十分な数を用意する
- **多様性**: データが均一すぎないこと。NULLカラム、異なる長さの文字列、多様な状態のレコードを含む
- **再現性**: 毎回同じデータが生成されること。ランダムを使う場合は seed を固定する

## アクセス権限

### 読み取り・編集可能
- `benchmark/seed_data.rb` — テストデータ定義
- `benchmark/setup.rb` — DBセットアップスクリプト
- コンテキストで指定された model, migration ファイル（スキーマ理解のため）

### 読み取りのみ
- `benchmark/config.yml` — 対象エンドポイントの確認
- `db/schema.rb` — 現在のスキーマ確認

### 変更禁止
- `benchmark/run.rb` — ベンチマークランナー
- controller, service のソースコード
- spec/ ディレクトリ

### Bash 制限（ホワイトリスト方式）
guard-bash-data-setup.sh により、以下のコマンドのみ許可:
- `RAILS_ENV=test ruby benchmark/setup.rb`
- `RAILS_ENV=test bin/rails db:migrate / db:rollback`

## 実行手順

1. コンテキストで渡された model とスキーマ情報を確認
2. `benchmark/seed_data.rb` の `TABLES` 定数と `seed!` メソッドを実装
3. `RAILS_ENV=test ruby benchmark/setup.rb` を実行してデータ投入を確認
4. 投入結果（各テーブルのレコード数）を報告
```

---

# 防御機構

AIに長時間自律的に行動させる以上、**暴走を防ぐ仕組み**が不可欠です。autoresearch では `prepare.py` を変更不可にするだけで済みましたが、多様なソースコードに触れるサーバーサイドのチューニングでは、より多層的な防御が必要になります。

AIの能力を引き出しつつ、行動の境界を明確に定める ── いわば「手綱（ハーネス）」の設計です。Claude Code の hooks やサブエージェントの権限分離を組み合わせて、AIが自律的に動ける範囲を制御しました。

## 防御層1: テストデータの隔離（Read hook）

tuning-agent が `benchmark/` 内のデータファイルを Read ツールで開こうとすると、hookスクリプトがこれをブロックします。

```bash
#!/bin/bash
# autoresearch-tuning-agent-block-read.sh

FILE_PATH=$(echo "$TOOL_INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

BLOCKED_PATTERNS=(
  "benchmark/seed_data"
  "benchmark/setup"
  "benchmark/run.rb"
)

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$FILE_PATH" | grep -q "$pattern"; then
    echo "BLOCKED: benchmark内部ファイルの読み取りは禁止されています: $FILE_PATH"
    exit 2
  fi
done

exit 0
```

## 防御層2: Bashコマンドのホワイトリスト制御

Read hook だけでは `cat benchmark/seed_data.rb` のようなBash経由の読み取りを防げません。そこで、Bashツールにもhookをかけ、**ホワイトリスト方式**で許可コマンドのみ実行可能にしました。

また`git push`、`git checkout main`、`git merge`、`rm -rf`、`bundle add` など全て許可リストに含まれないため、自動的にブロックされます。

↓重要な部分を抜粋しているのでこのままでは動きません
```bash
#!/bin/bash
# autoresearch-tuning-agent-guard-bash.sh（長いため抜粋）

ALLOWED_PATTERNS=(
  # --- Git（安全な操作のみ）---
  '^\s*git\s+add\s'
  '^\s*git\s+commit\s'
  '^\s*git\s+reset\s+--hard\s+HEAD~1\s*$'   # 1つ前の巻き戻しのみ
  '^\s*git\s+status'
  '^\s*git\s+diff'
  '^\s*git\s+log'
  '^\s*git\s+branch\s+--show-current'
  '^\s*git\s+stash'

  # --- spec / ベンチマーク ---
  '^\s*(RAILS_ENV=test\s+)?bundle\s+exec\s+rspec\s'
  '^\s*RAILS_ENV=test\s+ruby\s+benchmark/run\.rb'
  '^\s*RAILS_ENV=test\s+ruby\s+benchmark/setup\.rb'
  '^\s*RAILS_ENV=test\s+bin/rails\s+db:migrate'
  '^\s*RAILS_ENV=test\s+bin/rails\s+db:rollback'

  # --- 結果解析 ---
  '^\s*grep\s+.*\s+run\.log'
  '^\s*tail\s+.*\s+run\.log'

  # --- 基本ユーティリティ ---
  '^\s*echo\s'
  '^\s*cat\s+tuning_results\.tsv'
  '^\s*ls\s'
)

# etc......
```

## 防御層3: ブランチ保護

`perf-tune/` プレフィックスのブランチでのみ動作し、main や develop にいる場合は即座に停止します。これはソフト制約（SKILL.md / エージェント定義に記載）と、Bash hookによる `git checkout main` のブロックの両方で実現しています。

---

# PDCAサイクル ── 1サイクルの中で何が起きるか

tuning-agent は各サイクルで以下を実行します。

![](https://storage.googleapis.com/zenn-user-upload/d628864f600a-20260330.png)

重要なのは、6の記録が1の入力になるという**再帰構造**です。

tuning-agent は毎サイクル、過去の全試行を踏まえて次の手を考えます。「eager loading の追加で20%改善した」「メモ化は効果がなかった」── この蓄積された知見が、サイクルを重ねるごとにエージェントの改善精度を上げていきます。

## tuning_results.tsv ── 実際に試した記録

autoresearch が `results.tsv` に全実験を記録するように、autoresearch-controller も `tuning_results.tsv` に全サイクルの結果を記録します。
このファイルが次のサイクルのコンテキストとしてエージェントに渡されることで、AIは過去の成功と失敗から学んで次の改善案を立案できます。

弊社のパフォーマンスが悪いエンドポイントで試したところ、沢山の改善案が生まれ、サイクルを重ねるごとに着実にレスポンスタイムが改善していきました。

![](https://storage.googleapis.com/zenn-user-upload/1fcaf3349218-20260330.png)

---

# ベンチマークファイルの役割

プロジェクトの `benchmark/` ディレクトリに配置されるファイル群は、autoresearch における `prepare.py` に相当します。**AIが変更できない固定された評価基盤**です。

| ファイル | 役割 | 誰がアクセスできるか |
|---|---|---|
| `config.yml` | 対象エンドポイント・計測回数の設定 | tuning-agent (読み取りのみ) |
| `run.rb` | ベンチマーク実行スクリプト。エンドポイントにN回リクエストを送り、レスポンスタイムを計測 | 誰も読めない（実行のみ） |
| `setup.rb` | テストDBをクリーンにし、seed_data.rb を使ってデータを投入 | data-setup-agent のみ |
| `seed_data.rb` | テストデータの定義（レコード数、関連データ、多様性） | data-setup-agent のみ |

これらのファイルの具体的な実装はプロジェクトのアーキテクチャに依存します。SKILL.md のセットアップフェーズでテンプレートから自動生成されるため、使う側はエンドポイントとパラメータを指定するだけで構いません。プロジェクトやプログラミング言語により実装方針が異なり長文になるため、本ブログではここの具体のソースコードは割愛しますmm

---

# 実行の流れ

## 1. セットアップ（対話的）

```
> /autoresearch-controller setup UsersController#index

  → ブランチ作成: perf-tune/hoge-index
  → ベンチマークファイル生成
  → data-setup-agent がテストデータを設計・DB投入
  → ベースライン計測: avg 245ms, p95 312ms
```

## 2. 自律ループ開始

```
> /loop 10m /autoresearch-controller run

  → 10分ごとに tuning-agent が1サイクル実行
  → 人間は寝る
```

## 3. 結果確認

```
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

## 4. 成果の取り込み

perf-tune ブランチに keepされた変更だけが積み重なっているので、そのままPRにできます。

---

# 振り返り

## /loopコマンドの活用
`/autoresearch-controller run` を直接呼び出すのではなく、`/loop 10m /autoresearch-controller run` で呼び出す設計にしたのがポイントです。これにより、Claude Codeの標準機能を最大限活用しつつ、サイクルの重複を防ぎ、安定した自律ループを実現しています。

## ブラックリストからホワイトリストへ

当初、Bash hook はブラックリスト方式で実装しました。`git push` や `rm -rf` などの既知の危険コマンドをブロックする方式です。しかし「知らない危険」を防げないため、ホワイトリスト方式に切り替えました。

結果として、開発中に「`git stash` がブロックされた → 安全だから追加」「`rails runner 〇〇` が必要 → 追加」というサイクルが自然に回り、実運用に即したホワイトリストが育っていきました。

## 試行錯誤の資産化
現状、tuning-agent は過去の試行結果を「tuning_results.tsv の内容」としてテキストで受け取っています。これでも最低限の学習は可能ですが、試行錯誤の資産化のためには、これをCLAUDE.mdのようなコンテキストに永続化する仕組みも面白いと思っています。

---

# まとめ

autoresearch の「AIに実験を自律的にループさせる」という思想は、LLM訓練に限らず、**計測可能なPDCAサイクルが存在するあらゆる問題**に転用できますね。

今回はこれをRailsコントローラーのパフォーマンスチューニングに適用し、以下の3つを実現しました:

1. **autoresearch パターンの転用**: コード変更 → 計測 → keep/discard の自律ループを、サーバーサイドのレスポンスタイム改善に適用しました
2. **ハーネスエンジニアリング**: テストデータの隔離、Bashコマンドのホワイトリスト制御、ブランチ保護など、AIの暴走を防ぐ多層的な防御機構を構築することで、安全にAIが自律ループを回せる環境を整備しました
3. **再帰的PDCAサイクル**: 過去の試行結果がコンテキストとして蓄積され、AIの改善精度が向上していく構造を実現しました

特にハーネスエンジニアリングは昨今トレンドワードで、AIに自律的なタスクを任せる際に普遍的に必要になる考え方です。AIの能力を最大限引き出しつつ、暴走を防ぐ ── この両立が、AI時代のソフトウェアエンジニアリングの新しいスキルセットになっていくのではないでしょうか。

autoresearch のREADMEにある一節を引用して締めくくります:

> *The core idea is that you're not touching any of the Python files like you normally would as a researcher. Instead, you are programming the `program.md` Markdown files that provide context to the AI agents and set up your autonomous research org.*

今回やったのもまさにこれです。コードを直接書くのではなく、**AIの行動原理を設計する**。それが新しいエンジニアリングの形です。
