# はじめに

こんにちは、2列で並ぶ列に直列で並ぶことを選択した2人目、3人目の人は許しません。たろう眼鏡です。
クラシル社で、サーバーサイドの開発をしています。

AIのコードレビューツールをいくつか使っているのですが、Devin Reviewだけ指摘の質が異常に高いなと感じていました。別のチームのエンジニアからも同じ声が上がっていて、理由が気になったので公式ドキュメントや公式ブログを読んで、裏でどんな仕組みが動いているのかを調べました。

結論からいうと、Devin Reviewはdiffを見ているだけではなく、裏で4つの仕組みが動き、リポジトリ全体の文脈を理解しています。この記事ではそれぞれの仕組みを解説します。

# Devin Reviewの裏側にある4つの仕組み

## Layer 1: diff + worktree の選択的探索

分析の起点は PRのdiffです。ただ diffを見るだけではありません。

[公式ドキュメント](https://docs.devin.ai/work-with-devin/devin-review)によると:

> The CLI creates a git worktree in a cached directory to check out the PR branch.

> The Bug Catcher can execute a limited set of read-only operations scoped to the worktree directory

一時的な git worktree を作成し、その中で read-onlyのbashコマンドを実行して、diff外のファイルも選択的に参照します。許可されているコマンドは `ls`, `cat`, `pwd`, `file`, `head`, `tail`, `wc`, `find`, `tree`, `stat`, `du` と、検索系の `grep` です。

リポジトリ全体をアップロードするわけではなく、diffを起点にして必要なファイルを読みに行く仕組みです。

## Layer 2: 指示ファイルの自動取り込み

Devin Reviewはリポジトリ内の様々なAI系の設定ファイルを自動で認識して、レビューのコンテキストとして使います。

[公式ドキュメント](https://docs.devin.ai/work-with-devin/devin-review)によると:

対象となるファイルは:

- `**/REVIEW.md`, `**/AGENTS.md`, `**/CLAUDE.md`
- `**/CONTRIBUTING.md`
- `.cursorrules`, `.windsurfrules`, `*.rules`, `*.mdc`
- `.coderabbit.yaml`, `greptile.json`

`REVIEW.md` という専用の指示ファイルも使えます:

> REVIEW.md is a dedicated instruction file for Devin Review. Place it anywhere in your repository to customize how Devin reviews PRs in your project.

Devin Reviewは基本英語で指摘してくるので、「日本語で指摘すること」みたいな指示を書いておくのがおすすめです。

## Layer 3: Ask Devin セッション

ここが最も重要な層です。[Cognitionのブログ](https://cognition.ai/blog/devin-review)にこう書いてあります:

> Devin Review pipe your diffs into an inline Ask Devin session with full codebase understanding, so you can chat about the changes, without leaving the review.

Devin Reviewは diffを「full codebase understanding」付きの Ask Devin セッションに流して動いています。[Ask Devin](https://docs.devin.ai/work-with-devin/ask-devin) はコードベースに対する質問応答機能で、リポジトリインデックスをベースにした検索能力を持っています。

つまり Devin Reviewは、単に diffを見ているのではなく、コードベース全体の文脈を持った状態でレビューしている。Layer 1〜2で集めた情報に加えて、この Ask Devin セッションが「full codebase understanding」を提供しているわけです。

## Layer 4: DeepWiki + リポジトリインデックス

Devinはコードベースをバックグラウンドでインデックス化します（[Ask Devinのドキュメント](https://docs.devin.ai/work-with-devin/ask-devin)）:

> After connecting your GitHub, GitLab, or other source code provider, index your repository. Devin automatically indexes your codebase in the background, enabling powerful tools like DeepWiki and Ask Devin.

このインデックスの上に [DeepWiki](https://docs.devin.ai/work-with-devin/deepwiki) が構築されます:

> Devin now automatically indexes your repos and produces wikis with architecture diagrams, links to sources, and summaries of your codebase.

DeepWiki → Ask Devin の接続は明確で、[DeepWikiのドキュメント](https://docs.devin.ai/work-with-devin/deepwiki)に「Ask Devin will use information in the Wiki」と書かれています。Layer 3で見た通り Devin Reviewは Ask Devin セッション経由で動いているので、DeepWikiの情報は間接的にレビューにも効いていると考えられます。

# モデルは Claude Sonnet 4.5

Devin Reviewのモデルは **Claude Sonnet 4.5** です。[Cognitionのブログ](https://cognition.ai/blog/devin-sonnet-4-5-lessons-and-challenges)で公開されています。

ただ、この記事で書いてきた通り、指摘の鋭さはモデル単体の性能というよりは、worktree 探索 → 指示ファイル取り込み → Ask Devin → DeepWiki という4層の仕組みによるところが大きいと思います。同じ Claude Sonnet 4.5 でも、素の diffだけ渡してレビューさせた場合とは出力が全然違うはずです。

# Devin Reviewのメリット・デメリット

4つの仕組みを踏まえた上で、使ってみて感じたメリットとデメリットを整理します。

**メリット:**

- **diff の外にある問題を見つけられる**: Layer 1（worktree 探索）と Layer 3〜4（Ask Devin + インデックス）のおかげで、変更が他のファイルに与える影響を検出できる。diffだけ見るレビューツールでは構造的に見つけられない問題
- **PRを push するたびに再実行される**: webhook（opened, updated, reopened）でトリガーされるので、修正のたびに再レビューが走る。あるPRでは5回レビューが走り、前回の指摘が直っているかも再分析していた
- **無料**: 2026年4月現在、early release として無料で提供されている

**デメリット:**

- **スタイルやルール違反は指摘しない**: CLAUDE.md を読み込んでいるはずだが、必ずしも指摘に反映されているわけではない印象。コードの品質やスタイルの問題は指摘してこない。あくまで「バグっぽい問題」を見つける。
- **false positive もある**: 既存コードのバグを掘り起こすことがあるが、逆に既存の意図的な設計を「問題」として指摘してくるケースもある。本当に問題のこともあるので、デメリットというよりは注意点かもしれない。
