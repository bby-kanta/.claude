# はじめに

こんにちは、2列で並ぶ列に直列で並ぶことを選択した2人目、3人目の人を到底許すことができません。たろう眼鏡です。
クラシル社で、サーバーサイドの開発をしています。

AIのコードレビューツールをいくつか使っているのですが、Devin Reviewだけ指摘の質が異常に高いなと感じていました。別のチームのエンジニアからも多々同じ声が上がっていて、理由が気になったので公式ドキュメントや公式ブログを読んで、裏でどんな仕組みが動いているのかを調べました。

結論からいうと、Devin ReviewはPRのdiffだけを見ているのではなく、リポジトリ全体の文脈を理解しています。この記事ではDevin Reviewの強みを解説 & 私の考察を共有します。

# Devin Reviewの裏側にある4つの仕組み

## Layer 1: Bug Catcher

分析の起点はPRのイベントです。

[公式ドキュメント](https://docs.devin.ai/work-with-devin/devin-review)によると:

> 自動レビューのトリガー条件:
> - PRがオープンされたとき（ドラフトを除く）
> - PRに新しいコミットがpushされたとき
> - ドラフトPRがReady for reviewになったとき
> - 登録ユーザーがReviewerまたはAssigneeに追加されたとき

Devin Reviewが動くと、Bug Catcherが自動で解析します:

> The Bug Catcher automatically analyzes your PR for potential issues and displays findings in the Analysis sidebar. Findings are organized into two categories: Bugs and Flags.

検出結果は**Bugs**（修正すべきエラー）と**Flags**（情報提供を目的とした注釈）の2カテゴリに分類されます。

- BugsはSevere（即対応）とNon-severe（要確認）の2段階で、Devin Reviewが修正すべきと確信した問題です。
- FlagsはInvestigate（要調査）とInformational（補足説明）に分かれています。修正必須とは限らないが、レビュアーが知っておくべき情報や潜在的な問題を指摘します。

このように重大度で分類されるので、本当に直すべき問題が分かりやすくなっており、指摘の質が高いと感じる理由の一つになっています。

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

Devin Reviewは基本英語で指摘してくるので、とりあえず「日本語で指摘すること」みたいな指示を書いておくのがおすすめです。

## Layer 3: コードベース全体の探索

Bug CatcherはPRのdiffだけを見ているわけではありません。[Cognition公式のポスト](https://x.com/cognition/status/2016261335198400735)によると:

> Devin Review's bug catcher goes beyond just analyzing the code that was changed in a PR. It also scans the broader codebase to understand how changes might interact or interfere with existing code.
> If it comes across any pre-existing bugs or issues, it'll report those too!

変更が既存コードとどう干渉するかを調べるために、コードベースを広く探索しています。探索の過程で既存のバグを見つけた場合はそれも報告します。

ただ、具体的にどうやって探索しているかはブラックボックスです。grepやfindのようなシンプルなコマンドベースの探索なのか、もっと別の仕組みがあるのか。この点については次の考察セクションで掘り下げます。

### 考察: Ask DevinとDeepWikiはレビューにも効いているのか

Devin ReviewのUI上のレビュー画面にはチャット欄があります。[Cognitionのブログ](https://cognition.ai/blog/devin-review)によると、ここではPRのdiffが自動的にAsk Devinセッションに注入されています:

> Devin Review pipe your diffs into an inline Ask Devin session with full codebase understanding, so you can chat about the changes, without leaving the review.

つまりUI上でPRについて質問すると、diffの差分とリポジトリ全体を把握した上で回答が返ってきます。PRに関するAIとのやり取りはここで完結できます。

[Ask Devin](https://docs.devin.ai/work-with-devin/ask-devin)はリポジトリインデックスをベースにしたコードベース検索機能で、その上に[DeepWiki](https://docs.devin.ai/work-with-devin/deepwiki)が構築されています:

> After connecting your GitHub, GitLab, or other source code provider, index your repository. Devin automatically indexes your codebase in the background, enabling powerful tools like DeepWiki and Ask Devin.

[DeepWikiのドキュメント](https://docs.devin.ai/work-with-devin/deepwiki)には「`Ask Devin will use information in the Wiki`」とも書かれており、Ask Devinの回答にはDeepWikiの情報も活用されていることがわかります。Ask Devinの回答の質が高いのは、DeepWikiを通じてリポジトリ全体の文脈を理解できているからですね。

ここからは完全に妄想ですが、Bug Catcherのコードベース探索にもこのAsk Devin経由でのDeep Wikiを活用する仕組みが使われていたりしないかなと期待しています。

grepやfindでdiff外のファイルを読みに行くのは他のAIレビューツールでも良くやっていますが、他のツールとは一線を画す指摘の質の高さなので、何か独自の仕組みを入れているのではないかと想像しています。リポジトリインデックスとDeepWikiという検索基盤がすでにあって、チャット欄ではそれをAsk Devin経由で活用している。であれば、Bug Catcherも同じ基盤を使ってコードベースを探索していてもおかしくないなと。

現在Cognition社にはこの仕組みを問い合わせています。意図的に仕組みを非公開にしている可能性が高いので、良い回答は得られないかもしれませんが、何かわかったら追記します。

# Devin Reviewのメリット・デメリット

4つの仕組みを踏まえた上で、使ってみて感じたメリットとデメリットを整理します。

**メリット:**

- **diffの外にある問題を見つけられる**: 変更が他のファイルに与える影響を検出できる。diffだけ見るレビューツールでは構造的に見つけられない問題
- **PRを push するたびに再実行される**: webhook（opened, updated, reopened）でトリガーされるので、修正のたびに再レビューが走る。あるPRでは5回レビューが走り、前回の指摘が直っているかも再分析していた
- **無料**: 2026年4月現在、early release として無料で提供されている

**デメリット:**

- **スタイルやルール違反の指摘はマチマチ**: CLAUDE.md を読み込んでいるが、必ずしも指摘に反映されているわけではない印象。
- **false positive もある**: 既存コードのバグを掘り起こすことがあるが、逆に既存の意図的な設計を「問題」として指摘してくるケースもある。本当に問題のこともあるので、デメリットというよりは注意点です。
