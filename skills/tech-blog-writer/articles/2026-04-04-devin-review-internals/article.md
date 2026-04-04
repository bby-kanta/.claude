# Devin Review の指摘がなぜ鋭いのか、公式ドキュメントで裏を取った

こんにちは、2列で並ぶ列に直列で並んだ2人目、3人目の人は許しません。たろう眼鏡です。

クラシル社でうさポの開発をしています。AIのコードレビューツールをいくつか使っているのですが、Devin Review だけ指摘の質が異常に高いな感じていました。別のチームのエンジニアからも同じ声が上がっていて、「なんで鋭いんだろう」と気になったので公式ドキュメントや公式ブログを読み込んで、裏でどんな仕組みが動いているのかを調査してみました。

結論からいうと、Devin Review は diffを見ているだけではなく、裏で5つの仕組みが動いています。この記事ではそれぞれの仕組みを解説します。

## Layer 1: diff + worktree の選択的探索

分析の起点は PR の diff です。ただ diff を見るだけではありません。

[公式ドキュメント](https://docs.devin.ai/work-with-devin/devin-review)によると:

> The CLI creates a git worktree in a cached directory to check out the PR branch.

> The Bug Catcher can execute a limited set of read-only operations scoped to the worktree directory

一時的な git worktree を作成し、その中で read-only の bash コマンドを実行して、diff 外のファイルも選択的に参照します。許可されているコマンドは `ls`, `cat`, `pwd`, `file`, `head`, `tail`, `wc`, `find`, `tree`, `stat`, `du` と、検索系の `grep` です（[同ドキュメント](https://docs.devin.ai/work-with-devin/devin-review)より）。

リポジトリ全体をアップロードするわけではなく、diff を起点にして必要なファイルを読みに行く仕組みです。

使ってみて感じたのは、diffに含まれていないファイルに書いてあるルールやアーキテクチャ知識を参照しているパターンが多いです。

## Layer 2: 指示ファイルの自動取り込み

Devin Review はリポジトリ内の様々なAI系の設定ファイルを自動で認識して、レビューのコンテキストとして使います。

[公式ドキュメント](https://docs.devin.ai/work-with-devin/devin-review)によると:

> If any of these files exist, they'll be used as context when analyzing your PR.

対象となるファイルは:

- `**/REVIEW.md`, `**/AGENTS.md`, `**/CLAUDE.md`（大文字小文字問わず）
- `**/CONTRIBUTING.md`
- `.cursorrules`, `.windsurfrules`, `*.rules`, `*.mdc`
- `.coderabbit.yaml`, `greptile.json`

うちのリポジトリだと `CLAUDE.md` と `.claude/rules/rewards/` 配下の `spec.md`, `controllers.md`, `services.md` などが該当します。これらにはテストの書き方、Controller の責務、Service 層の設計パターンなどが書いてあるので、Devin がプロジェクト固有のルールを把握した上でレビューしている可能性があります。

ただ、実際に使ってみた感覚では、CLAUDE.md のルールに基づいた指摘（たとえば「`receive` ではなく `have_received` を使うべき」のようなテストスタイル違反）が出てくることはほぼありませんでした。読み込んではいるけど、ルール違反を網羅的に検出する用途には使っていないようです。

あと、`REVIEW.md` という専用の指示ファイルも使えます:

> REVIEW.md is a dedicated instruction file for Devin Review. Place it anywhere in your repository to customize how Devin reviews PRs in your project.

重点的にチェックしてほしい領域、よくあるアンチパターン、無視するディレクトリなどを指定できます。

## Layer 3: リポジトリの自動インデックス

Devin はリポジトリを接続した時点で、コードベースをバックグラウンドでインデックス化します。

[公式ドキュメント](https://docs.devin.ai/onboard-devin/index-repo)によると:

> After connecting your GitHub, GitLab, or other source code provider, index your repository. Devin automatically indexes your codebase in the background.

このインデックスが Layer 4 の Knowledge と Layer 5 の DeepWiki の基盤になっています。

## Layer 4: Knowledge — トリガーベースの知識想起

Devin には永続的な知識システムがあります。リポジトリの README や `.rules` ファイルから自動で知識が生成され、レビュー時に関連する知識がトリガーベースで想起される仕組みです。

[公式ドキュメント](https://docs.devin.ai/product-guides/knowledge)によると:

> Devin will automatically generate repo knowledge based on the existing READMEs, file structure and contents of the connected repositories.

> Devin retrieves Knowledge when relevant, not all at once or all at the beginning.

「全部の知識を最初にロードする」のではなく、「関連する知識をそのとき必要なタイミングで取り出す」という設計です。レビュー対象の diff に応じて、関連するアーキテクチャ知識やコーディングルールが動的に引き出されるということになります。

さらに、`.rules`, `.mdc`, `.cursorrules`, `CLAUDE.md`, `AGENTS.md` などのファイルからも自動で Knowledge が更新されます（[同ドキュメント](https://docs.devin.ai/onboard-devin/knowledge-onboarding)）:

> Devin will automatically pull and update Knowledge based on specialized files in your codebase including .rules, .mdc, .cursorrules, .windsurf, CLAUDE.md, and AGENTS.md.

つまり CLAUDE.md に書いた内容は、Layer 2（レビュー時のコンテキスト）と Layer 4（永続的な Knowledge）の両方に反映される可能性があります。

## Layer 5: DeepWiki + Ask Devin — コードベース全体の理解

最後の層が DeepWiki と Ask Devin の連携です。

[DeepWiki のドキュメント](https://docs.devin.ai/work-with-devin/deepwiki)によると:

> DeepWiki automatically indexes your repos and produces wikis with architecture diagrams, links to sources, and summaries of your codebase.

リポジトリのアーキテクチャ図やコードベースの要約が自動生成され、Ask Devin がこの情報を参照してコードの質問に答えます。

で、[Cognition のブログ](https://cognition.ai/blog/devin-review)にこう書いてあります:

> Devin Review pipes your diffs into an inline Ask Devin session with full codebase understanding

diff を「full codebase understanding」付きの Ask Devin セッションに流すという説明です。単に diff を見ているのではなく、DeepWiki と Knowledge を通じてコードベース全体の文脈を持った状態でレビューしている、というのが公式の説明です。

## 実際のPRで感じた傾向

いくつかのPRで使ってみて、Devin Review が得意なパターンと苦手なパターンが見えてきました。

**得意なパターン:**

- テンプレートメソッドパターンなどの継承で、子クラスがオーバーライドすべきメソッドを漏らしているケース
- `joins` と `eager_load` の重複、LIKE クエリのインジェクション、ページネーションの不安定性など Rails 固有のアンチパターン
- 変更が別モジュールの複数ファイルに影響するクロスモジュール依存

これらはいずれも diff だけでは気づけない問題で、worktree での探索やリポジトリインデックスが効いていると思われます。

**苦手（というか対象外）なパターン:**

- テストのスタイルガイド違反（CLAUDE.md に書いてあっても指摘しない）
- ドキュメントの不備やコメントの品質
- マジックストリングや定数化の指摘

Layer 2 で CLAUDE.md を読み込んでいるはずですが、ルール違反の網羅的なチェックには使っていないようです。Devin Review の方針として、スタイルよりバグの検出を優先しているのだと思います。

**PR 更新のたびに再実行される:**

PR の webhook（opened, updated, reopened）でトリガーされるため、PR に push するたびにレビューが再実行されます。あるPRでは5回レビューが走り、前回の指摘が修正されているかも含めて再分析していました。

## モデルは Claude Sonnet 4.5

Devin Review のモデルは **Claude Sonnet 4.5** です。[Cognition のブログ](https://cognition.ai/blog/devin-sonnet-4-5-lessons-and-challenges)で公開されています。

ただ、この記事で書いてきた通り、指摘の鋭さはモデル単体の性能ではなく、worktree 探索 → 指示ファイル取り込み → リポジトリインデックス → Knowledge → DeepWiki という5層の仕組みによるところが大きいと思います。同じ Claude Sonnet 4.5 でも、素の diff だけ渡してレビューさせた場合とは出力が全然違うはずです。

## REVIEW.md を書くと精度が上がるかもしれない

今回の調査で一番実践的だなと思ったのは、`REVIEW.md` でレビューをカスタマイズできる点です。

[公式ドキュメント](https://docs.devin.ai/work-with-devin/devin-review)によると、REVIEW.md に書ける内容は:

- 重点的にチェックしてほしい領域
- よくあるアンチパターン
- プロジェクトの規約やスタイル
- 無視するファイルやディレクトリ
- セキュリティやパフォーマンスの考慮事項

うちのリポジトリは CLAUDE.md と `.claude/rules/` を整備しているので、これが Layer 2 と Layer 4 経由で Devin にも効いている可能性があります。逆に言えば、CLAUDE.md を書いていないリポジトリでも `REVIEW.md` を書けば同じ効果が得られるかもしれません。

:::message
Settings > Review > Review Rules からファイルの glob パターンを追加すると、レビュー時に参照するファイルを増やせます。スキーマファイルや設定ファイルなど、diff に含まれないけどレビューに必要なファイルがある場合に使えます。
:::

## まとめ

Devin Review の指摘が鋭い理由は、5つの仕組みが裏で動いているからでした。

| Layer | 仕組み | 公式ソース |
|-------|--------|-----------|
| 1 | diff + worktree の read-only 探索 | [docs.devin.ai](https://docs.devin.ai/work-with-devin/devin-review) |
| 2 | CLAUDE.md / .rules 等の自動取り込み | [同上](https://docs.devin.ai/work-with-devin/devin-review) |
| 3 | リポジトリの自動インデックス | [docs.devin.ai](https://docs.devin.ai/onboard-devin/index-repo) |
| 4 | Knowledge（トリガーベース知識想起） | [docs.devin.ai](https://docs.devin.ai/product-guides/knowledge) |
| 5 | DeepWiki + Ask Devin（full codebase understanding） | [docs.devin.ai](https://docs.devin.ai/work-with-devin/deepwiki), [cognition.ai/blog](https://cognition.ai/blog/devin-review) |

CLAUDE.md を整備しているプロジェクトなら、それが Devin Review にも効いている可能性があります。まだ書いていなければ `REVIEW.md` から始めてみるのもありです。

Happy reviewing! 🎉
