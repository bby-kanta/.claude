# 複数のAIレビューツールを同時に走らせたら、全員一致は0件だったので、見逃しパターンをCLAUDE.mdにちりばめる

# はじめに

こんにちは！「PayPayで！」バーコードリーダーを画面に直接押し当てられるのが苦手です。たろう眼鏡です。
クラシル社でサーバサイドの開発をしています。

コードレビューの自動化は全エンジニア共通の課題なので、自分で仕組みを作らなくてもAnthropicがどんどん公式で良いツールを出すのではと楽観してます(~~ メンテナンスしたくない ~~)。現にAnthropic が code-review や pr-review-toolkit のプラグインを出しています。他人のふんどしで相撲を取ることに生涯を捧げてきたたろう眼鏡としては、これらのツールに乗っかるだけでレビューの自動化を進めたいです。

ただ、プラグインをそのまま使うだけだとレビューの質にばらつきがあります。ツールによって検出する問題がかなり違うし、あるツールが見つけたバグを別のツールはスルーしていたり、2回実行したら別の指摘がでたり。じゃあ複数の既製ツールを走らせて見逃しパターンを可視化し、その知識を CLAUDE.md・SKILLS・Rulesに蓄積していけば、少なくともAnthropic製のレビューツールの質は上がるのでは？と思いました。

この記事では、AnthropicだけでなくCodex・Devinを含む、5つのAIレビュアーを並列実行して見逃しパターンを分析し、CLAUDE.mdなどにコンテキストを蓄積させる仕組みについて紹介します。

## 使ったレビューツール5つ

前半4つは Claude Code のサブエージェントとして並列実行し、Devin は GitHub App として別途動かしています。

| ツール名 | 提供元 | リンク |
|---------|--------|--------|
| code-review | Anthropic 公式プラグイン | [Github リポジトリ](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/code-review) |
| pr-review-toolkit | Anthropic 公式プラグイン | [Github リポジトリ](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/pr-review-toolkit) |
| Codex review | OpenAI Codex プラグイン | [Github リポジトリ](https://github.com/openai/codex-plugin-cc) |
| Codex adversarial-review | OpenAI Codex プラグイン | [Github リポジトリ](https://github.com/openai/codex-plugin-cc) |
| Devin Review | Cognition (GitHub App) | [公式ドキュメント](https://docs.devin.ai/work-with-devin/devin-review) |

同じ Anthropic 製でも code-review と pr-review-toolkit は全く違う性格のツールですし、Codex review と Codex adversarial-review も内部的な仕組みが違います。Devin Review は他のツールとは毛色が違いますが、クラシル社で活用しているので比較のために入れてます。

全てが違う観点で動く以上、違うことを指摘するのは当たり前ですが、並列で動かすことで2点メリットがあります。

- 単一レビューより多角的な視点でより多くの問題を検出できる
- コンテキストの不備で指摘できなかったパターンを、他レビューの指摘をきっかけに発見できる場合がある

## 複数PRに走らせて見えた各ツールの性格

10個のPRに対して繰り返し走らせた結果、各ツールの「性格」がかなりはっきり見えてきました。

### CR（code-review）

[プラグインのソースコード](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/code-review)を読むと、プロンプトで以下の5観点のレビューを指示していることが分かります。

1. CLAUDE.md 準拠チェック
2. 変更箇所のみの浅いバグスキャン
3. git blame / コミット履歴に基づくレビュー
4. 過去PRのコメントとの照合
5. コード内コメントとの整合性チェック

各指摘に対して 0〜100 の信頼度スコアを付け、CLAUDE.md 起因の指摘はダブルチェックが入り、**スコア80未満はすべてフィルタされます**。プラグインの設計意図（5並列 + 信頼度スコアリング）がサブエージェント経由だと劣化している可能性はありますが、レビュー結果自体はルール違反やバグを正確に検出できているので実用上は問題ありませんでした。

面白いのはバグスキャンに対して "avoid reading extra context beyond the changes" と**意図的に diff の外を読まないよう指示している**ことです。CR が diff 外の問題をスルーするのはモデルの限界ではなく、偽陽性を減らすための設計判断でした。

CLAUDE.md や Rules に書いてあることは正確に引用して指摘してくれます。逆に Rules に書かれていない問題はほぼスルーします。パフォーマンスやアーキテクチャの問題には踏み込みません。

10PR 走らせた中で面白かったのは、PR本文が未記入のケースを critical として指摘したことです。CLAUDE.md の PR テンプレートルールに基づいた判定で、コード品質だけでなくプロジェクトのメタデータ規約も厳格に見ています。

### pr-review-toolkit

code-review と比べると3〜4倍の指摘を出す体感です。

内部で6つの専門サブエージェント（コードレビュー、テスト分析、サイレント失敗検出、コメント分析、パフォーマンス分析、スタイルチェック）が動いていて、多角的にPRを分析します。

code-review にはない強みが3つあります:

- **パフォーマンス分析**: `pluck` → `select` の最適化、N+1、不要な `includes` を検出する。あるPRでは code-review がスルーした `pluck` 問題を critical として指摘しました
- **設計・アーキテクチャの指摘**: Fat Controller の分割提案、コード重複のリファクタリング案を具体的に出す
- **運用リスクの検出**: 「この変更、RDB側の登録は確認済み？」「Slack承認フローの考慮が漏れてない？」のような、コードだけでは見えないビジネスプロセス上のリスクを指摘する

ただ、code-review と比べるとノイズも多い。10PR の集計で指摘の62%が suggestion レベルだったので、「本当に直すべき問題」が埋もれがちです。

もう一つ、リファクタリング系のPRで面白い検出がありました。diff には含まれない既存テストが、変更対象のメソッドの内部実装を直接モックしていて、リファクタリングでテストが壊れるリスクを指摘していました。diff の外のファイルを読みに行く能力は code-review にはない pr-review-toolkit の強みです。

### Codex review

Codex review と adversarial-review は内部的にまったく別の仕組みで動いています。プラグインのソースコードを読んで分かったことを書きます。

Codex review はプラグインが `review/start` API を叩くと、Codex 側の**専用レビューモード**に入ります。内部的には `enteredReviewMode` → コマンド実行 → `exitedReviewMode` というライフサイクルがあり、汎用のプロンプト実行とは別の仕組みです。プラグインからはレビュー対象の種別（branch か working-tree か）だけを渡して、何をどう調べるかは Codex 側に完全に委ねています。

このとき Codex は **read-only サンドボックス**内で動きます。リポジトリのファイルは自由に読めるけど書き込みはできない。実行ログを見ると、`rg` や `sed` でファイルを次々に読みに行っているのが分かりました。あるPRでは差分の変更ファイルを起点に、5〜6ファイルを芋づる式に辿っていました。

この「read-only サンドボックスでリポジトリを自由に探索できる」という仕組みが、diff に含まれないファイルとの不整合を検出する力につながっています。既存の同種実装を探して新実装と比較する動きもするので、「既存はこうなっているのに新しいほうだけ抜けている」という差分の検出にも効きます。

10PR 走らせた中で印象的だったのは、パフォーマンスベンチマークのPRで p95 計算のバグ（実際には max を返していた）を検出したケースです。Anthropic 系の2ツールも Codex adversarial も見逃していて、Codex review だけが気づきました。アルゴリズムの正しさを検証する能力は他のツールにはない強みです。

### Codex adversarial-review

adversarial-review は専用レビューモードではなく、**カスタムプロンプト + 構造化JSON出力**で動きます。実装上の違いとして、review は対象種別だけ渡して Codex 任せにするのに対し、adversarial はプラグイン側で事前に git diff や commit log を収集してプロンプトに埋め込みます。

プラグイン内の [`prompts/adversarial-review.md`](https://github.com/openai/codex-plugin-cc/blob/main/plugins/codex/prompts/adversarial-review.md) にプロンプトテンプレートがあり、「デフォルトで懐疑的であれ」「コストの高い失敗を優先しろ」という指示が明示的に入っています。攻撃面として認証・データ破損・冪等性・レースコンディション・スキーマドリフトなどが列挙されていて、モデルの探索方向をガイドしています。

出力もフリーテキストではなく、verdict（approve / needs-attention）、severity、confidence スコア付きの構造化JSONで返ってきます。スタイルやネーミングのフィードバックは出すなという制約もあるので、重要な指摘だけに絞られます。

冪等性、例外処理の rescue が後続ロジックを止めないケース、下流のバリデーションとの不整合など、実装者が「うまくいくケース」しか想定していないときに刺さる指摘が多いです。指摘は少ないですが、見つけた場合のインパクトが大きい。既存コードに潜んでいた設計上の穴を掘り起こすこともあります。

あるPRでは、スタッフが編集した招待コードがモデル側の生成ルール（8文字の大文字英数）を満たさないまま保存できてしまう問題を検出しました。モデルの生成ロジックは暗黙的に形式を定義しているけど、バリデーションとしては明示されていない。こういう「暗黙の契約違反」を見つけるのは adversarial ならではです。

### Devin Review

個人的にはDevin Reviewの指摘はかなり筋のいいものが多い印象です。
というのも、Devin Reviewはコードベース全体の文脈を理解した上でレビューしているからです。コチラの記事でDevin Reviewの仕組みを解説したので、興味がある方はぜひ読んでいただきたいです。

## なぜ見逃すのか — 5つの原因分類

「なぜ他のツールは見逃したのか」を分析したところ、5つの原因に分類できました。

### 1. diff スコープ制限

変更対象外のファイルの内容を把握していないと検出できない問題。code-review と pr-review-toolkit は基本的に diff の範囲内で分析するため、diff 外のファイルに依存する問題は構造的に検出できません。

たとえば「新しい定数を追加したが、その定数を参照すべき別ファイルのホワイトリストに追加し忘れた」のような問題は、ホワイトリスト側のファイルを知らないと指摘できません。

### 2. ドメイン知識不足

プロジェクト固有の仕様を知らないと検出できない問題。「サービスAとサービスBで使う認証トークンやAPI クライアントが異なる」といった知識は、既存実装を横断的に読まないと得られません。

### 3. プロジェクトルール非参照

CLAUDE.md や Rules ファイルを参照していないと検出できない問題。Codex と Devin はプロジェクト固有のコーディングルールを参照しないため、ルール違反は検出対象外になります。

### 4. 探索深度不足

下流のコードを十分に追跡していないと検出できない問題。メソッドAがメソッドBを呼び、メソッドBの内部挙動に起因するバグがある場合、メソッドBの実装まで追いかけて初めて問題が見えます。

### 5. 重要度判定の差異

問題自体は認識しているが、閾値以下と判断して報告しなかったケース。code-review が「重要度: 低」として軽く触れた問題を、pr-review-toolkit が「Important」として正式に指摘していることが実際にあります。

もっと極端な例もありました。あるPRで RAILS_ENV のガード処理が不十分な問題に対して、code-review は suggestion（コーディング規約レベル）、Codex review と adversarial は critical（本番データ破壊のリスク）と判定しています。同じ問題なのに重要度が3段階も違う。code-review は「コードとして正しいか」を見ていて、Codex 系は「本番で何が起きるか」を見ている。評価軸が違うので、重要度が逆転します。

5ツールそれぞれの得意・不得意を整理するとこうなります:

| 原因 | code-review | pr-review-toolkit | Codex review | Codex adversarial | Devin |
|------|------------|------------------|-------------|-------------------|-------|
| diff スコープ制限 | 弱い | 弱い | **強い** | **強い** | **強い** |
| ドメイン知識 | 普通 | 普通 | 普通 | 普通 | **強い** |
| ルール参照 | **強い** | 強い | 弱い | 弱い | 弱い |
| 探索深度 | 弱い | 普通 | **強い** | **強い** | 強い |
| 重要度判定 | 保守的 | やや積極的 | 適切 | やや過激 | 適切 |

code-review と pr-review-toolkit の差がはっきり出ているのがわかると思います。code-review はルール参照に特化した精密射撃で、pr-review-toolkit は探索深度と重要度判定のバランスが違います。

## Cross-Reviewer Analysis — レビューのレビューを自動化する

複数のレビュー結果を毎回手動で比較するのは現実的ではないので、横断分析を自動化する仕組みを作りました。Claude Code の Custom Skill として実装しています。

やっていることは3ステップです。

**Step 1: 指摘の構造化**

各レビュアーの指摘を統一スキーマに正規化します。重要度の表記がツールごとに違う（code-review は「高/中/低」、Codex は「P1/P2/P3」、adversarial は「high/medium/low」）ので、`critical / high / important / suggestion / info` の5段階に統一します。

```
指摘ID: {ツール名}-{連番}  (例: code-review-1, pr-review-toolkit-1, codex-review-1)
file: 対象ファイルパス
severity: critical | high | important | suggestion | info
category: bug | security | performance | convention | tests | architecture
summary: 1行サマリー
requires_repo_context: Yes/No（diff外の知識が必要か）
```

**Step 2: 意味的重複の検出とギャップ分類**

同じファイル・同じ問題を指摘しているものをグルーピングして、以下に分類します:

- **全員一致**: 全ツールが検出
- **多数一致**: 3つ以上が検出
- **Anthropic系共通**: code-review と pr-review-toolkit だけが検出
- **Codex系共通**: Codex review と adversarial-review だけが検出
- **X-only**: 1ツールだけが検出（ここがギャップ）

出力はこんな感じの重複マッピング表です:

```markdown
| 問題 | code-review | pr-review-toolkit | Codex review | Codex adversarial | Devin | 重要度の差異 |
|------|------------|------------------|-------------|-------------------|-------|-------------|
| テストルール違反 | critical | important | - | - | - | code-reviewが厳格 |
| パフォーマンス問題 | - | critical | - | - | - | pr-review-toolkit単独 |
| 下流の表示テキスト未登録 | - | - | high | - | important | 独立検出 |
| メソッドオーバーライド漏れ | - | - | - | - | critical | Devin単独 |
```

**Step 3: 見逃し原因の分析**

X-only（1ツールだけが検出）の指摘について、なぜ他のツールが見逃したのかを先ほどの5分類で分析します。ここが Cross-Reviewer Analysis の核心です。

「diff スコープ制限」が原因の見逃しであれば、その知識を CLAUDE.md の Rules に事前知識として埋め込むことで、次回以降は code-review でも pr-review-toolkit でも検出できるようになります。

実際にこの分析から、特定のリソース追加時に下流のホワイトリストやレポーティングクエリへの追加を忘れないようにするチェックリストを Rules に追加しました。

## アーキテクチャ — 4並列サブエージェントの仕組み

Claude Code の Agent tool とカスタムエージェント定義を使って、4つのレビュアーを同時に起動しています。全体は2段構成です。

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

`hooks` で `PreToolUse` フックを定義し、Bash コマンドの実行前に `block-write-commands.sh` を走らせて `git push` や `rm` などの書き込み系コマンドをブロックしています。

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

Codex の出力は英語です。Codex が何を見つけたかを正確に記録したいので、エージェントには翻訳だけさせて独自の指摘は追加させません。

あと、Codex モデルが本当に実行されたか（Claude が自分でレビューを書いてないか）を検証するために、ジョブファイルの作成を確認するステップも入れています。実行証跡としてコマンド全文・終了コード・生出力をファイルに残すようにしているので、「誰がこの指摘を出したのか」が後から追えます。

### 並列実行

4つのエージェントは Agent tool の同一ターンで同時に起動します。

```
Agent(subagent_type="anthropic-code-reviewer", prompt="PR をレビュー...")
Agent(subagent_type="anthropic-toolkit-reviewer", prompt="現在のブランチをレビュー...")
Agent(subagent_type="codex-reviewer", prompt="ブランチの変更をレビュー...")
Agent(subagent_type="codex-adversarial-reviewer", prompt="ブランチの変更を批判的にレビュー...")
```

4つが並列で動くので、直列実行と比べて待ち時間はかなり短くなります。結果はメインエージェントが受け取って、`review-output/{リポジトリ名}/{PR番号}/` にファイルとして書き出します。

:::message
Devin は GitHub App として PR 作成時に自動でレビューが走るので、この並列実行の仕組みには含めていません。Devin のレビュー結果は GitHub API から取得して、Cross-Reviewer Analysis で他の4ツールと合わせて分析しています。
:::

## 考察 — 5つのツールをどう使い分けるか

### code-review と pr-review-toolkit は別物

同じ Anthropic 製プラグインですが、役割がまったく違います。

code-review は「プロジェクトの憲法に違反していないか」を厳密にチェックする番人です。指摘は少ないけど精度が高く、ルール違反を見逃すことはほぼない。pr-review-toolkit は「このPR、全体的に大丈夫？」を多角的に見る監査役。パフォーマンスや設計の問題を見つけてくれるけど、ノイズも混じります。

両方走らせるのが理想ですが、片方だけ選ぶなら用途次第です。ルール準拠を徹底したいなら code-review、PR全体の品質を底上げしたいなら pr-review-toolkit。

### Codex 系の強みは「diff の外」

Codex review と adversarial-review は、diff に含まれないファイルを `rg` で積極的に探索するのが最大の強みです。Anthropic 系のツールが構造的に検出できない「下流への影響」や「既存コードとの不整合」を補完してくれます。

adversarial は指摘が少ないぶん、見つけた問題のインパクトが大きい傾向にあります。冪等性の問題や、既存コードに潜んでいたバグを掘り起こすことも。

### Devin は PR が更新されるたびにレビューし直す

他の4ツールはこちらから明示的に実行するワンショットのレビューですが、Devin は PR の webhook で自動トリガーされるため、PR が更新されるたびにレビューが再実行されます。あるPRでは5回レビューが走り、前回の指摘が修正されているかを含めて再分析していました。

diff を起点に worktree 内で grep/find を使って選択的にコンテキストを取得するので、クロスモジュールの依存関係や Rails 固有のアンチパターンに強い。ただ CLAUDE.md のルールに基づいた指摘は出てこないので、テストスタイルやドキュメントの規約違反は検出対象外です。

### フィードバックループが本体

この仕組みの本当の価値は、並列レビュー自体ではなく **見逃しパターンのフィードバックループ** にあると思っています。

Cross-Reviewer Analysis で「なぜ見逃したか」を分析し、その知識を Rules やコード内コメントに還元すると、次回以降は code-review や pr-review-toolkit でも同じ問題を検出できるようになります。

見逃しパターンは一度踏んで初めて言語化できるものなので、分析を仕組み化しておくと Rules が着実に育っていきます。

## まとめ

10PR に複数のAIレビュアーを走らせた結果、ツールごとに検出する問題がかなり異なることが分かりました。同じ問題でも重要度が3段階ずれるケースがあり、ツールごとに評価軸が違います。code-review はルール違反を精密に検出し、pr-review-toolkit はパフォーマンスやリファクタリングの影響まで広く見る。Codex review は diff の外を探索してアルゴリズムの正しさまで検証し、adversarial は暗黙の契約違反を見つける。Devin は PR 更新のたびに再レビューして、開発サイクル中にフィードバックする。

Claude Code のサブエージェント機構を使えば、4つのレビュアーの並列実行から結果のファイル書き出しまで自動化でき、Cross-Reviewer Analysis で見逃しパターンを分析して Rules にフィードバックするループを回すのがポイントです。

「AIレビュー入れてるから大丈夫」ではなく「AIレビューが何を見逃しているか」を把握しておくと、レビューの質が一段上がると思います。ぜひ試してみてください！

Happy reviewing! 🎉
