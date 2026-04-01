# autoresearch-controller テンプレート

セットアップフェーズで以下のファイルをプロジェクトに生成する。
`{{VARIABLE}}` はセットアップ時にユーザー入力で置換する。

---

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

---

## benchmark/run.rb

```ruby
# frozen_string_literal: true
#
# Controller Tuner ベンチマークランナー
# !! このファイルはAIエージェントによる読み取り・変更が禁止されています !!
#
# 実行方法（Docker経由で実行すること。ホスト直実行はAWS等の初期化エラーが発生する）:
#   docker compose exec app bash -c "RAILS_ENV=test ruby benchmark/run.rb"
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

---

## benchmark/setup.rb

```ruby
# frozen_string_literal: true
#
# Controller Tuner DB セットアップ
# !! このファイルはAIエージェントによる読み取り・変更が禁止されています !!
# テストDBをクリーンにし、ベンチマーク用データを投入する
#
# 【設計ノート】
# - このプロジェクトはマルチDB構成（primary + primary_replica）
# - テスト環境では primary と replica が別データベース
# - コントローラーが connected_to(role: :reading) で replica を読むため、
#   両方にデータを投入する必要がある
# - replica へのコピーは INSERT SELECT + FK_CHECKS=0 で行う
#
require_relative "../config/environment" unless defined?(Rails)

Rails.env = "test" unless Rails.env.test?

require_relative "seed_data"

# replica DB の接続情報を取得
replica_config = ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "primary_replica")
primary_db = ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "primary").database

# primary をクリーン
ActiveRecord::Base.connection.execute("SET FOREIGN_KEY_CHECKS = 0") rescue nil
BenchmarkSeedData::TABLES.each do |table_name|
  ActiveRecord::Base.connection.execute("TRUNCATE TABLE #{table_name}")
rescue ActiveRecord::StatementInvalid
  ActiveRecord::Base.connection.execute("DELETE FROM #{table_name}")
end
ActiveRecord::Base.connection.execute("SET FOREIGN_KEY_CHECKS = 1") rescue nil

# primary にデータ投入
BenchmarkSeedData.seed!

# replica をクリーンにしてから primary のデータをコピー
replica_conn = ActiveRecord::Base.establish_connection(replica_config.configuration_hash).lease_connection
replica_conn.execute("SET FOREIGN_KEY_CHECKS = 0") rescue nil

BenchmarkSeedData::TABLES.each do |table_name|
  replica_conn.execute("TRUNCATE TABLE #{table_name}") rescue nil
  replica_conn.execute("INSERT INTO #{table_name} SELECT * FROM #{primary_db}.#{table_name}")
rescue => e
  puts "Warning: Failed to copy #{table_name} to replica: #{e.message}"
end

replica_conn.execute("SET FOREIGN_KEY_CHECKS = 1") rescue nil

# primary に接続を戻す
ActiveRecord::Base.establish_connection(:primary)

# 投入結果を出力（MySQL互換: .first が Array を返す場合に対応）
puts "Benchmark data seeded: #{BenchmarkSeedData::TABLES.map { |t| row = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM #{t}").first; count = row.is_a?(Hash) ? row.values.first : row.first; "#{t}(#{count})" }.join(", ")}"
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
# 【注意事項】
# - CarrierWave等のuploaderがmountされたカラムを持つモデルは
#   ActiveRecord.create! ではなく raw SQL INSERT を使う
#   例: ActiveRecord::Base.connection.execute("INSERT INTO ...")
# - 認証が必要な場合、config.yml の Authorization ヘッダーと
#   同じトークンで AuthToken を作成する
#
class BenchmarkSeedData
  # クリーン対象のテーブル一覧（setup.rbが使用）
  TABLES = [
    # 例: "users", "posts", "comments"
    {{TABLE_NAMES}}
  ].freeze

  def self.seed!
    # data-setup-agent がここにテストデータ生成ロジックを書く
    # 例:
    # 50.times do |i|
    #   user = User.create!(name: "User #{i}", email: "user#{i}@example.com")
    #   20.times do |j|
    #     user.posts.create!(title: "Post #{j}", body: "Content..." * 10)
    #   end
    # end
    {{SEED_LOGIC}}
  end
end
```

---

## tuning_results.tsv（初期状態）

```
commit	avg_ms	p95_ms	specs_passed	status	description
```

ヘッダー行のみ。タブ区切り（TSV）。カンマは description 内で使えるようにTSVを採用。

---

## 既知の落とし穴

### 1. ホスト直実行ではなくDocker経由で実行する
Shoryuken等のinitializerがAWS SSOトークンを要求してクラッシュするため、
ベンチマークは必ず `docker compose exec app bash -c "..."` で実行する。

### 2. Primary / Replica 別データベース問題
テスト環境では `retail_api_test` と `retail_api_test_replica` が別DB。
コントローラーが `connected_to(role: :reading)` で replica から読むため、
seed データを primary に投入しただけでは 404 になる。
setup.rb テンプレートの `INSERT INTO ... SELECT * FROM primary_db.table` パターンで対処済み。

### 3. FK制約の順序
replica へのデータコピー時、子テーブルが親テーブルより先にINSERTされるとFK違反になる。
`SET FOREIGN_KEY_CHECKS = 0` で一時的に無効化して対処。

### 4. MySQL の .first の戻り値
`ActiveRecord::Base.connection.execute("SELECT ...").first` は MySQL では Array を返す（Hash ではない）。
`.first.values.first` ではなく、型チェック付きで `.first` を使う。

### 5. CarrierWave uploader 付きカラム
`mount_uploader :icon, SomeUploader` が設定されたモデルは、
`Model.create!(icon: "dummy.png")` でバリデーションエラーになることがある。
raw SQL INSERT で直接値をセットする。
