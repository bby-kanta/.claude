---
name: cross-reviewer-analysis
description: Quad Reviewの4つのレビュー結果を横断的に分析し、レビュアー間の重複・固有指摘・重要度の差異をレポートするスキル。/anthropic-quad-review の後に実行する。
disable-model-invocation: true
---

# Cross-Reviewer Analysis

Quad Review（`/anthropic-quad-review`）で生成された4つのレビュー結果ファイルを横断的に分析し、レビュアー間のギャップ分析・見逃し原因分析・改善提案を生成する。

## 入力ファイル

以下の4ファイルを読み取る:

```
/Users/kuboderakanta/claude-review-plugin-diff/review-output/{リポジトリ名}/{PR番号}/
├── code-review.md              # Anthropic code-review の結果
├── pr-review-toolkit.md        # Anthropic pr-review-toolkit の結果
├── codex-review.md             # Codex review の結果
└── codex-adversarial-review.md # Codex adversarial-review の結果
```

## Codex ファイルのパース

Codex 系のファイル（`codex-review.md`, `codex-adversarial-review.md`）は3セクション構成:

1. `## 実行証跡` — コマンド全文・終了コード・生出力（**分析対象外**）
2. `## Codex ジョブログ` — ジョブの実行ログ（**分析対象外**）
3. `## レビュー結果` — 日本語に翻訳されたレビュー本文（**これが分析対象**）

分析時は `## レビュー結果` セクション以降のみを使用すること。

## ワークフロー

### Step 1: PR情報とレビューディレクトリの特定

引数でリポジトリ名とPR番号が指定されていればそれを使う。なければ:

1. 現在のブランチから `gh pr view --json number,headRepository` で取得
2. それでも取れなければユーザーに確認

レビューディレクトリ:
```
/Users/kuboderakanta/claude-review-plugin-diff/review-output/{リポジトリ名}/{PR番号}/
```

4ファイルすべてが存在するか確認する。存在しないファイルがあれば、存在するファイルのみで分析を進める（どのファイルが欠落しているかを最終レポートに記載）。

### Step 2: 4ファイルの読み込み

Read ツールで4ファイルを並列に読み込む。Codex系ファイルからは `## レビュー結果` セクション以降を抽出する。

### Step 3: 指摘の構造化

各レビュアーの指摘を以下のスキーマで構造化する:

```
指摘ID: {reviewer略称}-{連番}  (例: CR-1, PRT-1, CX-1, CXA-1)
reviewer: code-review (CR) | pr-review-toolkit (PRT) | codex-review (CX) | codex-adversarial-review (CXA)
file: 対象ファイルパス
severity: critical | high | important | suggestion | info
category: bug | security | performance | convention | tests | architecture | comments | other
summary: 1行サマリー
requires_repo_context: Yes/No（リポジトリの他ファイルを参照して初めて検出可能か）
```

各レビュアーの重要度表記は統一スケールにマッピングする:

| レビュアー | 元の表記 | 統一スケール |
|-----------|---------|------------|
| code-review | 高 | critical |
| code-review | 中 / important | important |
| code-review | 低 / suggestion | suggestion |
| pr-review-toolkit | Critical | critical |
| pr-review-toolkit | Important | important |
| pr-review-toolkit | Suggestion | suggestion |
| codex-review | P1 | critical |
| codex-review | P2 | high |
| codex-review | P3 | important |
| codex-adversarial-review | high | critical |
| codex-adversarial-review | medium | important |
| codex-adversarial-review | low | suggestion |

### Step 4: 意味的重複の検出とギャップ分類

#### 4a: 意味的重複マッピング

同じファイル・同じ問題を指摘しているものを「意味的重複」としてグルーピングする。判定基準:

1. **同一ファイル + 類似行番号** → 高確率で同一指摘
2. **異なるファイルだが同一の根本原因** → 根本原因でグルーピング
3. **類似カテゴリ + 類似内容** → 慎重に判断

#### 4b: ギャップ分類

グルーピング結果を以下に分類する。**ギャップ（X-only）の抽出がこのスキルの最重要出力である。**

- **全員一致** (4/4): 4つのレビュアーすべてが検出
- **多数一致** (3/4): 3つのレビュアーが検出
- **Anthropic系共通** (CR + PRT): Anthropic系2ツールのみが検出
- **Codex系共通** (CX + CXA): Codex系2ツールのみが検出
- **CR-only**: code-review のみが検出
- **PRT-only**: pr-review-toolkit のみが検出
- **CX-only**: codex-review のみが検出
- **CXA-only**: codex-adversarial-review のみが検出

### Step 5: 見逃し原因分析

**各 X-only 指摘について、なぜ他のレビュアーは見逃したのかを分析する。** これがこのスキルの核心的価値である。

各 X-only 指摘に対して以下を分析:

1. **見逃したレビュアー**: どのレビュアーが検出できなかったか
2. **見逃しの原因仮説**: なぜ検出できなかったか
   - diff スコープ制限（変更されていないファイルの知識が必要）
   - ドメイン知識不足（Rails/Ruby 固有の知識、ビジネスロジック理解）
   - プロジェクトルール非参照（CLAUDE.md / Rules を参照していない）
   - 重要度判定の差異（問題を認識していたが閾値以下と判断）
   - コンテキスト探索の深度不足（下流コードを追跡していない）
3. **再現性**: この見逃しパターンは他のPRでも再現しうるか
4. **対策可能性**: CLAUDE.md / Rules / SKILL / コード内コメントで対策可能か（配置先の判断は `/context-placement-strategy` スキルの基準に従う）

### Step 6: 分析レポートの生成

以下のフォーマットで Write ツールを使い `{output_dir}/cross-reviewer-analysis.md` に書き出す:

```markdown
# Cross-Reviewer Analysis: {リポジトリ名}#{PR番号}

> PR: {PRタイトル}
> 分析日: {YYYY-MM-DD}

## サマリー

| 指標 | 件数 |
|------|------|
| code-review 指摘 | **X件**（重要度内訳） |
| pr-review-toolkit 指摘 | **X件**（重要度内訳） |
| codex-review 指摘 | **X件**（重要度内訳） |
| codex-adversarial-review 指摘 | **X件**（重要度内訳） |
| 全員一致 (4/4) | **X件** |
| 多数一致 (2-3/4) | **X件** |
| Anthropic系のみ | **X件** |
| Codex系のみ | **X件** |
| 単独検出 | **X件** |

### 特記事項

（このPRの分析で特筆すべき傾向や逆転ケース等）

---

## 全指摘の構造化一覧

### code-review（X件）

| # | file | severity | category | summary | requires_repo_context |
|---|------|----------|----------|---------|----------------------|
| CR-1 | ... | ... | ... | ... | ... |

### pr-review-toolkit（X件）

| # | file | severity | category | summary | requires_repo_context |
|---|------|----------|----------|---------|----------------------|
| PRT-1 | ... | ... | ... | ... | ... |

### codex-review（X件）

| # | file | severity | category | summary | requires_repo_context |
|---|------|----------|----------|---------|----------------------|
| CX-1 | ... | ... | ... | ... | ... |

### codex-adversarial-review（X件）

| # | file | severity | category | summary | requires_repo_context |
|---|------|----------|----------|---------|----------------------|
| CXA-1 | ... | ... | ... | ... | ... |

---

## ギャップ分析

### 分類結果

| 分類 | 件数 | 内容 |
|------|------|------|
| **全員一致 (4/4)** | X件 | ... |
| **多数一致 (3/4)** | X件 | ... |
| **Anthropic系共通** | X件 | ... |
| **Codex系共通** | X件 | ... |
| **CR-only** | X件 | ... |
| **PRT-only** | X件 | ... |
| **CX-only** | X件 | ... |
| **CXA-only** | X件 | ... |

### 意味的重複マッピング

| 指摘 | CR | PRT | CX | CXA | 重要度の差異 |
|------|-----|------|-----|------|-------------|
| {問題名} | {ID}（重要度） | {ID}（重要度） | {ID}（重要度） | {ID}（重要度） | {差異の説明} |
| ... | - | ... | ... | - | ... |

---

## X-only ギャップ詳細

### Anthropic系のみの指摘（Codex系が見逃した指摘）

（各指摘の詳細）

#### なぜCodex系は見逃したのか？

（原因分析: diff スコープ制限 / ドメイン知識 / ルール非参照 / 探索深度不足 等）

### Codex系のみの指摘（Anthropic系が見逃した指摘）

（各指摘の詳細）

#### なぜAnthropic系は見逃したのか？

（原因分析）

### CR-only 指摘

（該当があれば詳細 + 他3ツールの見逃し原因分析）

### PRT-only 指摘

（該当があれば詳細 + 他3ツールの見逃し原因分析）

### CX-only 指摘

（該当があれば詳細 + 他3ツールの見逃し原因分析）

### CXA-only 指摘

（該当があれば詳細 + 他3ツールの見逃し原因分析）

---

## 対策困難な指摘（diff-scope-limitation）

diff に含まれないファイルの知識が必要な指摘をリストアップ。
これらはレビューツールの構造的限界であり、CLAUDE.md/Rules での対策が特に有効。

---

## ツール間比較の考察

### Anthropic系 (code-review vs pr-review-toolkit)

| 観点 | code-review | pr-review-toolkit |
|------|-------------|-------------------|
| 検出件数 | X件 | X件 |
| 最高重要度 | ... | ... |
| 偽陽性リスク | ... | ... |
| カバレッジ | ... | ... |
| 重要度の感覚 | ... | ... |
| Rulesファイル参照 | ... | ... |
| 独自の価値 | ... | ... |

### Codex系 (codex-review vs codex-adversarial-review)

| 観点 | codex-review | codex-adversarial-review |
|------|-------------|-------------------------|
| 検出件数 | X件 | X件 |
| 最高重要度 | ... | ... |
| 偽陽性リスク | ... | ... |
| カバレッジ | ... | ... |
| 重要度の感覚 | ... | ... |
| 独自の価値 | ... | ... |

### Anthropic系 vs Codex系

| 観点 | Anthropic系（2種合計） | Codex系（2種合計） |
|------|------------------------|---------------------|
| 検出件数 | X件（重複排除後） | X件（重複排除後） |
| 強み | ... | ... |
| 弱み | ... | ... |

### このPRにおける総合評価

（4つのレビュアーを総合した、このPRの品質に対する評価。
  どのレビュアーが最も価値のある指摘をしたか、どのレビュアーの指摘が偽陽性だったか等）

---

## 追記先の判断と改善提案

追記先（CLAUDE.md / Rules / SKILL / コード内コメント）の判断には `/context-placement-strategy` スキルの基準に従うこと。
各追記案を提示する際は、なぜその配置先が適切かの根拠も記載する。

### CLAUDE.md 追記案

（具体的な追記案、または「該当なし」）

### Rules 追記案

（具体的な追記案。ファイルパターンとルール内容を明記。または「該当なし」）

### SKILL 追記案

（具体的な追記案、または「該当なし」）

### コード内コメント案

（具体的なコメント案とファイルパスを明記。または「該当なし」）
```

### Step 7: 完了報告

```
## Cross-Reviewer Analysis 完了

- リポジトリ: {リポジトリ名}
- PR: #{PR番号}
- 出力: {output_dir}/cross-reviewer-analysis.md
```
