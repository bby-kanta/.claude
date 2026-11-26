<!-- コードの理解をやっぱり捨てたくない。Devin Botsでシームレスにコードの解説HTMLを読む -->
# はじめに

こんにちは、プロ野球のシーズンが終わって抜け殻です。たろう眼鏡です。

最近はコードを書くのはほぼAIです。自分の仕事は指示を出して、出てきた差分を確認することがメインです。

ただ、この「確認」がしんどいですよね。生成される量が多いうえに、関数を1つ読むたびに呼び出し先のprivateメソッドへ飛んで、戻ってきてまた飛ぶ、を繰り返すことになります。正直、読むの面倒臭いです。

とはいえ、自分で理解していないコードを本番に出すのは怖いです。なので、コードを読む作業を楽にする方向で工夫しました。

# 前提

1. 筆者は自律型AIエージェントはGrok BotとDevin Botsしか使ったことがないです。申し訳ないですが、ほかのBotの強みや弱みは良く知りません。
2. あと筆者はDevinが大好きです。なのでDevinのポジショントークになっている可能性があります。
3. Devin Botsが使いたくてしょうがなくて無理して使っている節があります。

他のAIエージェントでも本記事でやれることはきっとできるので、1つのアイデアとして参考にしてもらえればと思います。

# やったこと

簡単にいうと、Devin Desktopでコーディングしている途中にDevin Botsを呼び出して、対象のコードを解説するHTMLを作らせます。できたHTMLはDevin Desktopの右タブにそのままシームレスに表示されるので、左でセッションで対話を進めながら右でコードの解説を読めます。

![左にDevinのセッション、右にBotが作った解説HTMLを表示しているDevin Desktopの画面](https://static.zenn.studio/user-upload/b1cc38ce9bfe-20261127.png)

似たようなことはこれまでもやっていて、解説をPDFにしたり、AIが作ったHTMLをブラウザに貼り付けて開いたりセッション内でコードを解説させたりしていました。ただ、毎回ファイルを書き出してアプリを切り替えたり、導線が散らばるのが地味に面倒でした。今は作業中のDevin Desktop画面の右タブに即座に出せるので、自分にはこのシームレスな挙動が刺さりました。

この記事で紹介するのは以下の2つです。

- **Devin Desktop**: DevinのADE
- **Devin Bots**: 2026年11月17日に出た機能で、Botごとに指示と記憶を持ち、仕事に応じてDevinのセッションを立ち上げて並行で進めてくれる機能（[Introducing Devin Bots](https://devin.ai/blog/introducing-devin-bots)）

# 使い方

使い方の流れは以下の通りです。
実際の作業のイメージが付くように、Devin Desktop画面全体のスクリーンショットも添付します。

## 1. いつも通りDevinにコードを書かせる

記事用のサンプルとして、以下のような要件をDevinのセッションに投げて、ミニ図書室の本の貸出・返却を受け付けるAWS Lambda関数を作らせました。

- Pythonの標準ライブラリだけで、`handler.py`の1ファイルに収める
- 蔵書はコード内の辞書で、「月の図鑑」と「海の図鑑」の2冊
- `lambda_handler()`が`borrow`（借りる）と`return`（返す）の依頼を順番に処理し、`apply_request()`が`borrow_book()`か`return_book()`に振り分ける
- 貸出中の本の貸出、借りられていない本の返却、蔵書にない本の依頼は断り、状態を変えない
- `python handler.py`で6件のサンプル依頼を流せるようにする

`handler.py`ができて、ローカル実行の結果まで返ってきました。

![Devinがhandler.pyを作成し、6件のリクエストの実行結果を表で返している画面](https://static.zenn.studio/user-upload/05c99fc66a93-20261127.png)


ここまではいつものDevinです。

## 2. 入力欄の「+」からBotsを選ぶ

入力欄の左下にある「+」を押すと、リポジトリやファイル、スキルと並んで「Bots」があります。

![「+」メニューを開いた画面。リポジトリ、ファイル、スキル、Botsなどが並んでいる](https://static.zenn.studio/user-upload/fdb00910fad3-20261127.png)

## 3. Botを指定して依頼する

解説HTML用に作っておいたBotを選んで、「Botにhandler.py渡してHTMLを受け取って」と書いて送るだけです。

![入力欄でBotを指定し、handler.pyを渡すよう依頼している画面](https://static.zenn.studio/user-upload/fd5d4fcb6294-20261127.png)

:::message
**セッションのメニューからもBotに渡せます**

「+」から呼ぶ以外に、サイドバーのセッション一覧からもBotに渡せます。セッションの「…」メニューの「その他」に「Bot に昇格」と「Bot に移動」があり、「Bot に移動」を開くと作成済みのBotが並びます。

![セッションの「…」メニューから「その他」→「Bot に移動」を開き、作成済みのBotが一覧で表示されている画面](https://static.zenn.studio/user-upload/209bcc7fc3cd-20261127.png)

![](https://static.zenn.studio/user-upload/3ea319d799c7-20261127.png)

ここで解説用のBotを選ぶと、セッションごとBotに渡せます。依頼文は書いていませんが、Botがセッションの中身から何をすべきか判断して、解説HTMLを作ってくれました。

作業中のセッションをそのまま投げたいときはこちらが楽です。
:::

## 4. HTMLが返ってくる

Devinが`handler.py`の中身をBotに渡し、Botが解説HTMLを作ります。

Botの成果物はBot側のチャットに届くので、HTMLはいったんそちらに添付されます。それをDevinが拾って、こちらのセッションに転送してくれました。

![Botが作ったhandler_explained.htmlがセッションに添付されている画面](https://static.zenn.studio/user-upload/df6f1d480918-20261127.png)

## 5. 右タブで開く

添付されたHTMLを開くと、Devin Desktopの右タブに表示されます。左がセッション、右が解説です👇️

![左にDevinのセッション、右にhandler_explained.htmlを表示している画面](https://static.zenn.studio/user-upload/68853e19ff34-20261127.png)

画面を切り替えずに、左で作業を続けながら右で読めます。ブラウザやエディタを行き来しなくていいのがシームレスです。

# 解説HTMLの工夫

## 図で全体像を先に掴む
![](https://static.zenn.studio/user-upload/32aa021c93d9-20261127.png)

HTMLの冒頭には処理の流れと状態遷移の図があります。

左が`event → lambda_handler → apply_request → borrow_book / return_book → 返り値`という処理の流れです。右は本1冊が`available`と`borrowed`の間をどう行き来するかの状態遷移図で、「借りられていない本を返す」「貸出中の本を借りる」が失敗して状態が変わらないことも描かれています。

コードを1行目から読む前にこれを見ておくと、どこが入口でどこで分岐するのか分かった状態で読み始められます。

## コードブロック風の見た目

解説はすべてエディタっぽいコードブロックで、行番号とシンタックスハイライト付きです。各ブロックの左上には`L6-L12`のような行範囲のバッジがついているので、元のファイルのどこを読んでいるかが分かります。
![](https://static.zenn.studio/user-upload/38fdbbbe44df-20261127.png)

コードの下には行範囲ごとの説明が並びます。`borrow_book()`なら「L7-L8 蔵書にない」「L9-L10 貸出中」「L11-L12 状態を書き換えて成功」と、早期リターンの分岐が色分けされています。

## 呼び出し先のprivateメソッドを右横に並べる

今回一番大切にしたのが、呼び出し先の実装を見やすくすることです。

コードを読んでいて一番つらいのは、呼び出し先の実装を見に行くときです。プライベートメソッドなら下までスクロールする。関数なら別ファイルを開いて、読み終わったら元の場所を探して戻る。これを何度も繰り返すと、今どこを読んでいたのか分からなくなり心が折れ画面をそっと閉じます。

なので、ロジックの右横に呼び出し先の実装を並べるようにしました。

![](https://static.zenn.studio/user-upload/4c9003d9d6ea-20261127.png)

`apply_request()`の右には`borrow_book()`と`return_book()`がタブで並んでいます。左のコードで波線のついた関数名をクリックすると、右のタブが切り替わります。`lambda_handler()`の右には`apply_request()`が出ています。

スクロールせずに「呼び出し元」と「呼び出し先」を同時に見られるので、読むときの往復がなくなりました。勝ちました。

## 実行トレースで具体的な値を追う

最後に、サンプルイベント6件を順に処理したときの結果と、処理後の蔵書の状態が表になっています。

![](https://static.zenn.studio/user-upload/2feaf603daac-20261127.png)

2件目で「貸出中です」、4件目で「借りられていない本です」になり、そのあいだ状態が変わっていないことが表で確認できます。コードを頭の中で実行しなくて済むので楽です。

## 最後に改善案を出させる（ただし絶対に直させない）

せっかくコードをAIに読ませたので、ついでに「気になった点」として最後に改善案を出させています。

![](https://static.zenn.studio/user-upload/beba0fcc633a-20261127.png)

今回は「`"borrow"`以外はすべて返却扱いになる」という指摘が出ました。`apply_request()`が`else`で受けているので、`"retrun"`のような打ち間違いも`return_book()`に流れます。ほかにも、キーがないと`KeyError`で落ちる点や、状態の文字列がベタ書きされている点が挙がっていました。

ただ、このBotの役割はHTMLを作り理解の手助けをすることだけです。改善案は出しますが、コードは修正しないように指示しています。冒頭にも「以下は改善の提案で、修正はしていません」と書かれています。

直すかどうかは読んだ人間が判断して、必要なら元のセッションでDevinに頼めばいいので、Botの責務は解説に絞りました。

# Botの設定

本Botに渡している指示は「デザインのルール」と「コードリーディング」の2つだけです。どちらもBotとやりとりしながら決めたもので、Botの設定画面の「メモリ」に2つに分かれて入っています。

![](https://static.zenn.studio/user-upload/5314f9e43eb2-20261127.png)

1つ目が役割と進め方で、2つ目がHTMLのデザインルールです。要点はこんな感じです。

- 役割はコードの解説だけで、実装はしない。改善案は「気になった点」に書くが直さない
- 解説は毎回、サイドのタブで見られる1つのHTMLファイルで返す
- Bot自身はコードを読み書きせず、依頼をそのまま子セッション（軽量モデル）に渡す
- 呼び出し先の関数は波線を引き、コードの右横に並べて表示する（左右の幅は7:3）

:::details メモリ1: 役割と進め方

```text
Memory
Standing preferences and instructions go here; topical detail goes in other files anywhere in this drive (any directory structure).

- Role (set by the owner): explain code in clear Japanese when called; do not implement. Explain by meaningful chunks (quote code, then "このコードは..."), not strictly line by line. Only if the user says it's needed, open a child-branch PR with line-by-line code comments for visual review. Improvement opinions are allowed, but implementing them is not my responsibility. Role is a draft being refined with the owner. [source: devin-b524b6b4ecc741c9a2c44ecc1922fd5a; added: 2026-11-26; confidence: high]
- Workflow (owner-confirmed): triggered mainly by a PR URL, also by a file path. Audience is the PR author. End explanations with a separate "気になった点" section; never fix them. Line-comment child-branch PR and comments on the original PR: propose only, create only on explicit user request. [source: devin-b524b6b4ecc741c9a2c44ecc1922fd5a; added: 2026-11-26; confidence: high]
- Output format (owner rule, mandatory): every explanation is delivered as one self-contained HTML file (attached, viewable in the side tab), visually easy to read. [source: devin-b524b6b4ecc741c9a2c44ecc1922fd5a; added: 2026-11-26; confidence: high]
- HTML design rules: see html-design.md (mandatory for every explanation). [source: devin-b524b6b4ecc741c9a2c44ecc1922fd5a; added: 2026-11-26; confidence: high]
- Bot itself does as little as possible: no code reading or writing; dispatch to child sessions (cheap lightweight model) with the owner's message forwarded verbatim; never trade away quality. Keep improving handoff efficiency: when a handoff causes rework, add the fix as a rule here (format/design rules live in memory so children read them). Follow-ups on the same PR go to the same child. [source: devin-b524b6b4ecc741c9a2c44ecc1922fd5a; added: 2026-11-26; confidence: high]
- Handoff gotcha: children must attach the updated HTML file in their final message every time they revise it (one child reported "sent" without attaching).
```

:::

:::details メモリ2: HTMLのデザインルール

```text
HTML explanation design rules

- Owner wants HTML explanations rich in diagrams and color, not plain. Code blocks get editor-style syntax highlighting (VS Code Dark+ like, line numbers). Include flow/sequence diagrams; color roles: blue normal, green success, red errors, yellow concerns; overview diagram + TOC at top; chunk cards of code + "このコードは..."; 気になった点 as colored severity badges. [source: devin-b524b6b4ecc741c9a2c44ecc1922fd5a; added: 2026-11-26; confidence: high]
- When a chunk calls a private/helper function (same file or repo), underline the call (wavy) and show that function's implementation in a side panel next to the code block (two columns: caller left, callee right; click the wavy name to show it), not stacked vertically, with its own explanation, so the reader never has to trust the prose blindly. [source: devin-b524b6b4ecc741c9a2c44ecc1922fd5a; added: 2026-11-26; confidence: high]
- Headers: each code chunk gets a line-range header like "L1-L5" (source file line numbers); each side-panel callee gets a clear header naming the called private function (e.g. "呼び出し先: fetch_statuses()"). [source: devin-b524b6b4ecc741c9a2c44ecc1922fd5a; added: 2026-11-26; confidence: high]
- Layout: full-width, no centered max-width container; content should fill large monitors. [source: devin-b524b6b4ecc741c9a2c44ecc1922fd5a; added: 2026-11-26; confidence: high]
- Gotcha: the HTML generator template adds its own centered wrapper (max-w-2xl / 42rem / 960px) and a duplicate title; remove the wrapper itself, and verify full width with a screenshot in a wide window before attaching. [source: devin-b524b6b4ecc741c9a2c44ecc1922fd5a; added: 2026-11-26; confidence: medium]
- Side panel width: caller:callee about 7:3, proportional to screen width (not fixed px).
```

:::

# Devin Botsのいいところ

Devin Botsを使って感じたメリットを紹介します。
「Skillsで良くない？」と思う方もいらっしゃると思うので、その部分についても触れていきます。

## 作業中のセッションのコンテキストを汚さない

個人的にはこれがSkillsと比べて一番の大きな違いです。

Skillsは今のセッションの中で動くので、コードの解説をさせるとその読み込みや解説のやりとりがまるごと作業中のコンテキストに積まれます。それを避けたければ、解説用に別の子セッションを立てたり、必要なファイルや前提を別セッションに渡し直す必要があります。

Botは自分のチャットを持っていて、実際の作業はBotが立ち上げた別のセッションで進むことが前提です（[Devin Bots（Devin Docs）](https://docs.devin.ai/work-with-devin/bots)）。なので、作業中のセッションからは雑にBotを呼ぶだけで済みます。セッションを分ける作業をしなくても、解説HTMLだけが手元に返ってきて、作業中のコンテキストは綺麗に保てます。

## クラウド上なのでチームで育てられる

Devin Botsはクラウド上で動きます。手元のPCに置いたプロンプトファイルを各自で育てるのとは違って、1つのBotをチームで共有して使えます。

作ったばかりのBotは作成者だけのものですが、共有するとメンバーごとに「Can use」「Can configure」「Can share」の権限を付けられます。指示を書き換えられるのは「Can configure」を持つ人だけで、共有したBotの記憶は使う人全員で共有されます（[Devin Bot access and security](https://docs.devin.ai/work-with-devin/bots/access-and-security)）。

なので、誰かがデザインルールを直せば、次からチーム全員の解説HTMLに反映されます。
自分だけで育てたいなら、「Can use」だけにすればいいです。

セッション自体もクラウド上にあるので、ほかのメンバーもすぐに見られます。レビュアーが解説HTMLを見たくなったら、セッションを開いてもらえば普通に見れます。手元で作ったPDFやHTMLのように、いちいちどこかにアップロードして共有する手間が省けます。

## Botの利用料金を個別に追える

Botの利用量は「Botとのチャット」と「Botが立ち上げたすべてのセッション」の合計で視覚的に確認できます。Botごとに今期どれだけ使ったかを確認でき、管理者向けの「Bots」ページには全Botの作成者・利用量・上限が並びます（[Devin Bot usage limits](https://docs.devin.ai/work-with-devin/bots/usage-limits)）。

Botの設定画面の「使用量上限」では、請求サイクルごとのオンデマンド上限を決められます。今回のBotは「個別の使用量上限」にして、上限を$40にしました。

![](https://static.zenn.studio/user-upload/5889f3bfd06f-20261127.png)

今の請求サイクルでこのBotが使ったのは$11.97で、12月2日にリセットされることまで1画面で分かります。解説HTMLのように気軽に何度も呼ぶ用途だと、そのBotにいくらかかっているかを他の作業と分けて見られるのは助かります。

:::message
$11.97はBotを作るときの検証でぶん回しまくった分の合計です。この記事で紹介したセッションでは$1もかかっていません。
:::

これはSkillsとの違いでもあると思っています。Slillsは作って配っても、実際に使われているのかが見えにくいです。Botは利用量がBotごとに残るので、ちゃんと使われているのか、実は今は誰も使っていないのかが数字で分かります。

使われていないと分かれば、直すなり消すなり判断できます。「作ったきり誰も使わないまま形骸化する」ということが起きにくいのではと感じました。

## Botと作業でモデルを分けてコストを抑える

Botの設定画面の「エージェントモード」では、2つのモデルを別々に選べます。

- **オーケストレーター**: 人間や他のBotとチャットし、計画して委任する役
- **セッション**: Botが立ち上げるセッションで、コードを書いてテストする役

今回はオーケストレーターをDevin Fusion、セッションをSWE-2 Flash Medium (Preview)にしています。

![](https://static.zenn.studio/user-upload/9e0e1ba8a6af-20261127.png)

Devin Fusionは計画やレビューを担うフロンティアモデルで、コードを書く時のみコストの低いモデルを組み合わせて動かすなどを柔軟に行えるCognitionの仕組みです（[Introducing Fusion in Devin Desktop & CLI](https://cognition.com/blog/local-fusion)）。SWE-2 FlashはCognitionが2026年11月4日に出したコーディング用モデルで、SWE-2の5分の1の価格、3倍の速度とされています（[Introducing SWE-2 Flash](https://cognition.com/blog/swe-2-flash)）。

解説HTMLの作成はデザインルールに沿ってコードを読むだけなので、手を動かす側はSWE-2 Flashで十分でした。毎回フロンティアモデルで回すと気軽に呼べなくなるので、ここは意図的に軽いモデルを選んでいます。

## BotがBotを呼ぶ（今後やりたいこと）

この記事では使っていませんが、Devin BotsはBot同士で連携できます。公式の例では、QA Botがバグを見つけたらDeveloper Botを呼んで直させる、という流れが紹介されています（[Devin Bots](https://devin.ai/bots)）。

人間のチームのように、Botに仕事を任せてBotが別のBotに振る形が作れます。今回の解説Botもそのメンバーに入れて、実装Botが書いたコードを解説Botが図解して人間に渡す、みたいなBotのチームを作ってみたら面白そうだなと思ってます。

# まとめ

コードはAIに書かせながら、読む作業はDevin BotsにHTMLを作らせて楽にしました。

- Devin Desktopの右タブに解説を出して、セッションも並行で稼働させながらコードも理解しにいく
- 呼び出し先の関数を右横に並べて、スクロールやファイル移動をなくす
- 図と実行トレースで、コードを読む前に全体像と具体的な値を掴む
- 改善案は出させるが、修正はさせない
- Devin Botsの使用モデルは軽量にしてコストを抑える

Happy code reading! 📖
