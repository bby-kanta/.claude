# 5つのAIにコードレビューさせたら、全員一致は0件だった

こんにちは、AIレビュアーを増やしすぎて「で、結局どれを信じればいいの？」と途方に暮れています。たろう眼鏡です。

dely でクラシルリワードの開発をしています。最近メンバーのアウトプットが早すぎて、気づいたらPRレビューに追われる日々です。AIのコードレビューツールをいくつか試してきたのですが、ある日ふと「こいつら全員に同じPRをレビューさせたら、どれくらい意見が一致するんだろう」と気になりました。

やってみた結果: **22件の指摘が出て、5ツール全員が一致した指摘は0件**でした。

この記事では、Claude Code のサブエージェント機構を使って4つのAIレビュアーを並列実行する仕組みと、レビュー結果を横断分析して「なぜ見逃すのか」を可視化する Cross-Reviewer Analysis について紹介します。

## 使った5つのレビュアー

今回使ったのは以下の5つです。前半4つは Claude Code のサブエージェントとして並列実行し、Devin は GitHub App として別途動かしています。

| レビュアー | 提供元 | ざっくりした特徴 |
|-----------|--------|---------------|
| **code-review** | Anthropic公式プラグイン | 精密射撃型。CLAUDE.md のルール違反を正確に検出する |
| **pr-review-toolkit** | Anthropic公式プラグイン | 広域探索型。テスト・セキュリティ・設計まで幅広く見る |
| **Codex review** | OpenAI Codex プラグイン | 文脈探索型。diff の外まで追いかけて下流への影響を調べる |
| **Codex adversarial-review** | OpenAI Codex プラグイン | 攻撃者視点型。リプレイ攻撃や権限の抜け穴を探す |
| **Devin** | Cognition (GitHub App) | 継承パターン網羅型。オーバーライド漏れに強い |

簡単にいうと、Anthropic 系は「diff の中を精密に見る」、Codex 系は「diff の外まで追いかける」、Devin は「既存コードとの整合性を見る」という傾向があります。狙ったわけではなく、結果的にそうなりました。

## 同じPRに5つ走らせた結果

対象は、既存のジョブクラスをテンプレートメソッドパターンで継承して新しいエンドポイントを追加するPRです。親クラスの `perform` メソッドを共有しつつ、`coin_reason` や `apply_campaign` を子クラスでオーバーライドする設計になっています。

結果はこうなりました:

| 指標 | 件数 |
|------|------|
| code-review の指摘 | 3件 |
| pr-review-toolkit の指摘 | 11件 |
| Codex review の指摘 | 2件 |
| Codex adversarial-review の指摘 | 2件 |
| Devin の指摘 | 4件 |
| **全員一致** | **0件** |
| 2ツール以上が一致 | 5件 |
| 1ツールだけが検出 | 12件 |

全22件のうち半分以上が「1ツールだけが検出した指摘」です。どれか1つだけ使っていたら、残りは見逃していたことになります。

### 各ツールだけが見つけた指摘の例

具体的にどんな指摘が single-tool detection だったかを見てみます。

**Devin だけが見つけた critical バグ**: 子クラスが親クラスの `send_push_notification` をオーバーライドしていなかったため、usapo ユーザーにメインアプリ（hops）向けのプッシュ通知が送信される問題。FCM トークンの取得元、送信クラス、ディープリンクの3つすべてが間違ったアプリのものになっていました。

**Codex review だけが見つけた問題**: 新しいコイン付与 reason が SnowflakeQuery のレポーティングクエリの集計対象に含まれておらず、管理画面のレポートが過少報告になる問題。diff に含まれない `lib/snowflake_query/` のファイルを `rg` で探索して発見しています。

**Codex adversarial-review だけが見つけた問題**: 同じ `trans_uuid` でリプレイされた場合に `RecordNotUnique` の rescue が処理を停止せず、コインの重複付与が発生する冪等性の問題。これは新規コードではなく、既存の親クラスに潜んでいたバグです。

**Anthropic 系だけが見つけた問題**: テストで `receive` の代わりに `have_received` を使うべきというプロジェクトルール違反。`.claude/rules/rewards/spec.md` に定義されたルールを正確に引用して指摘しています。

## なぜ見逃すのか — 5つの原因分類

個人的に一番面白かったのがここです。single-tool detection の指摘について「なぜ他のツールは見逃したのか」を分析したところ、5つの原因に分類できました。

### 1. diff スコープ制限

変更対象外のファイルの内容を把握していないと検出できない問題。Anthropic 系のツールは基本的に diff の範囲内で分析するため、diff 外のファイルに依存する問題は構造的に検出できません。

例: SnowflakeQuery のレポーティングクエリ、ギフト交換バリデーションのホワイトリスト

### 2. ドメイン知識不足

プロジェクト固有の仕様を知らないと検出できない問題。usapo とリワードで FCM トークンや送信クラスが異なるという知識は、`app/services/usapo/` 配下の既存実装を読まないと得られません。

例: プッシュ通知のオーバーライド漏れ（Devin だけが検出）

### 3. プロジェクトルール非参照

CLAUDE.md や Rules ファイルを参照していないと検出できない問題。Codex と Devin はプロジェクト固有のコーディングルールを参照しないため、ルール違反は検出対象外になります。

例: `receive` → `have_received` ルール、`assert_response_schema_confirm` の使用

### 4. 探索深度不足

下流のコードを十分に追跡していないと検出できない問題。`UserCoins.update_coin` の内部で unique key が渡されない場合にランダム生成される挙動まで追跡して、初めて冪等性の問題が見えてきます。

例: リプレイ時のコイン重複付与（Codex adversarial だけが検出）

### 5. 重要度判定の差異

問題自体は認識しているが、閾値以下と判断して報告しなかったケース。code-review は `subject` の二重呼び出しを「重要度: 低」として記載しましたが、pr-review-toolkit は同じ問題を「Important」として正式に指摘しています。

ツールごとの弱点をまとめるとこうなります:

| 原因 | Anthropic 系 | Codex 系 | Devin |
|------|-------------|---------|-------|
| diff スコープ制限 | 弱い | **強い**（積極的に探索） | 強い |
| ドメイン知識 | 普通 | 普通 | **強い**（既存実装を参照） |
| ルール参照 | **強い**（CLAUDE.md 準拠） | 弱い | 弱い |
| 探索深度 | 弱い | **強い**（下流追跡） | 普通 |
| 重要度判定 | 保守的 | 適切 | 適切 |

## Cross-Reviewer Analysis — レビューのレビューを自動化する

5つのレビュー結果を毎回手動で比較するのは現実的ではないので、横断分析を自動化する仕組みを作りました。Claude Code の Custom Skill として実装しています。

やっていることは3ステップです:

**Step 1: 指摘の構造化**

各レビュアーの指摘を統一スキーマに正規化します。重要度の表記がツールごとに違う（code-review は「高/中/低」、Codex は「P1/P2/P3」）ので、`critical / high / important / suggestion / info` の5段階に統一します。

**Step 2: 意味的重複の検出とギャップ分類**

同じファイル・同じ問題を指摘しているものをグルーピングして、「全員一致」「多数一致」「Anthropic系のみ」「Codex系のみ」「X-only」に分類します。

**Step 3: 見逃し原因の分析**

X-only（1ツールだけが検出）の指摘について、なぜ他のツールが見逃したのかを5分類で分析し、CLAUDE.md や Rules への改善提案を生成します。

出力はこんな感じの Markdown ファイルです:

```markdown
## 意味的重複マッピング

| 問題 | CR | PRT | CX | CXA | DV | 重要度の差異 |
|------|-----|------|-----|------|-----|-------------|
| receive → have_received | CR-1 (critical) | PRT-3 (important) | - | - | - | 実質同じ |
| REASON_TEXT 未登録 | - | - | CX-2 (high) | - | DV-3 (important) | CX と DV が独立検出 |
| push通知誤送信 | - | - | - | - | DV-1 (critical) | Devin のみ |
```

この分析で特に価値があるのは「対策困難な指摘」のリストアップです。diff に含まれないファイルの内容が必要な指摘は、レビューツールの構造的な限界なので、CLAUDE.md の Rules に事前知識として埋め込むのが有効です。

実際にこの分析から、coin reason 追加時のチェックリスト（下流の REASON_TEXT、ギフト交換バリデーション、SnowflakeQuery への追加を忘れないようにするルール）を Rules ファイルに追加しました。

次回以降、同じパターンの見逃しは Anthropic 系ツールでも検出できるようになります。

## アーキテクチャ — 4並列サブエージェントの仕組み

Claude Code の Agent tool と カスタムエージェント定義を使って、4つのレビュアーを同時に起動しています。全体は2段構成です。

```
Stage 1: /anthropic-quad-review（並列レビュー実行）
  → 4エージェント同時起動 → 結果をファイルに書き出し

Stage 2: /cross-reviewer-analysis（横断分析）
  → 4ファイルを読み込み → ギャップ分析 → レポート生成
```

### エージェント定義

各レビュアーは `~/.claude/agents/` に Markdown ファイルとして定義しています。frontmatter でツール権限やモデル、hooks を指定します。

```yaml
# ~/.claude/agents/anthropic-code-reviewer.md
---
name: anthropic-code-reviewer
description: code-review プラグインを実行する読み取り専用レビューエージェント
tools: Read, Grep, Glob, Bash, Skill, WebFetch
model: opus
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: ~/.claude/hooks/block-write-commands.sh
---
```

ポイントは `hooks` の部分です。`PreToolUse` フックで Bash コマンドの実行前に `block-write-commands.sh` を走らせて、`git push` や `rm` などの書き込み系コマンドをブロックしています。

```bash
#!/bin/bash
# block-write-commands.sh
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

BLOCKED=(
  "^git push" "^git merge" "^git rebase" "^git reset"
  "^gh pr merge" "^gh pr close" "^gh pr comment"
  "^rm " "^mv "
)

for pattern in "${BLOCKED[@]}"; do
  if [[ "$COMMAND" =~ $pattern ]]; then
    echo "ブロック: レビューエージェントでは書き込み操作は許可されていません" >&2
    exit 2
  fi
done
```

レビューエージェントが暴走してPRにコメントを書いたり、ファイルを消したりしないようにするガードレールです。

### Codex 連携の工夫

Codex 系のエージェントは少し特殊で、**自分自身ではコードを読まない**ように制約しています。代わりに `codex-companion.mjs` を Bash で実行して、Codex モデルにレビューさせます。

```bash
node ~/.claude/plugins/marketplaces/openai-codex/plugins/codex/scripts/codex-companion.mjs \
  review --wait --scope branch 2>&1
```

Codex の出力は英語なので、エージェントが日本語に翻訳してから返します。翻訳のみで独自の指摘は追加させません。Codex が何を見つけたかを正確に記録したいからです。

あと、Codex モデルが本当に実行されたか（Claude が自分でレビューを書いてないか）を検証するために、ジョブファイルの作成を確認するステップも入れています。

### 並列実行

4つのエージェントは Agent tool の同一ターンで同時に起動します。

```
Agent(subagent_type="anthropic-code-reviewer", prompt="PR #7983 をレビュー...")
Agent(subagent_type="anthropic-toolkit-reviewer", prompt="現在のブランチをレビュー...")
Agent(subagent_type="codex-reviewer", prompt="ブランチの変更をレビュー...")
Agent(subagent_type="codex-adversarial-reviewer", prompt="ブランチの変更を批判的にレビュー...")
```

4つが並列で動くので、順番に実行するよりだいぶ速いです。結果はメインエージェントが受け取って、`review-output/{リポジトリ名}/{PR番号}/` にファイルとして書き出します。

## 考察 — 複数の AI レビュアーを使う意味

### 単体では不十分

今回の結果で分かったのは、どのツールも単体では critical レベルのバグを見逃すということです。Devin だけがプッシュ通知のバグを見つけ、Codex だけがレポーティングの問題を見つけ、Anthropic だけがルール違反を見つけました。1つだけ選んで使っていたら、残りは人間が見つけるしかありません。

### 相互補完的な組み合わせ

面白いのは、各ツールの強みがきれいに補完関係にあることです。

- **Anthropic 系**: ルール準拠 + diff 内の精密分析
- **Codex 系**: diff 外の下流影響 + セキュリティ
- **Devin**: 既存コードとの整合性 + 継承パターンの網羅性

「全部使えばいいじゃん」という話ではあるのですが、5ツール分のレビューを毎回読むのは正直つらい。なので Cross-Reviewer Analysis で差分だけを抽出するようにしています。

### フィードバックループが本体

この仕組みの本当の価値は、並列レビュー自体ではなく **見逃しパターンのフィードバックループ** にあると思っています。Cross-Reviewer Analysis で「なぜ見逃したか」を分析し、その知識を Rules やコード内コメントに還元すると、次回以降は Anthropic 系ツールでも同じ問題を検出できるようになります。

今回の分析から実際に追加したルール:

- coin reason 追加時の下流チェックリスト（REASON_TEXT、ギフト交換バリデーション、SnowflakeQuery）
- テンプレートメソッドパターンで子クラスを作る際のオーバーライド漏れ防止ルール

こういう知識は1回見逃して初めて言語化されるものなので、「見逃しの分析」を仕組み化しておくと、レビュー基盤の Rules が着実に育っていきます。

## まとめ

同一PRに5つのAIレビュアーを走らせた結果、全員一致は0件で、半数以上が1ツールだけの検出でした。見逃し原因は「diff スコープ制限」「ドメイン知識不足」「ルール非参照」「探索深度不足」「重要度判定の差異」の5つに分類できます。

Claude Code のサブエージェント機構を使えば、4つのレビュアーを並列で動かして結果をファイルに書き出すところまで自動化できます。Cross-Reviewer Analysis で見逃しパターンを分析し、Rules にフィードバックするループを回すと、ツール単体の限界を徐々に補えるようになります。

「AIレビュー入れてるから大丈夫」ではなく「AIレビューが何を見逃しているか」を把握しておくのが大事だなと実感しました。

Happy reviewing! 🎉
