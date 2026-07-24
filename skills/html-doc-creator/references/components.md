# コンポーネントカタログ

テンプレートの CSS に定義済みのコンポーネント一覧。内容に合うものを選んで `<main>` 内に配置する。
すべてのスニペットはコピーしてそのまま使える。

## 使い分け早見表

| 内容 | 使うコンポーネント |
|---|---|
| 結論・最終判断を最初に見せたい | verdict（結論カード） |
| 対象ごとのステータス比較（2〜4件） | verdict-grid（サマリカード） |
| 指摘・課題・リスクを深刻度付きで列挙 | finding（指摘カード）＋ pill |
| 構造化データ・比較表・チェックリスト | table（.table-wrap） |
| 処理の流れ・時系列・多段パイプライン | flow（フロー図） |
| 状態・深刻度・カテゴリのラベル | pill |
| 補足・脚注レベルの情報 | .note |
| 箇条書きの列挙 | ul |

---

## ヘッダー（doc-header）

全文書で必須。eyebrow は「文書種別 · 対象 · 日付」の 3 点セット。

```html
<header class="doc-header">
  <p class="eyebrow"><strong>調査レポート</strong> · retail-api · 2026-07-24</p>
  <h1>タイトル（疑問文や結論文が読みやすい）</h1>
  <p class="lead">リード文。結論から書き、<b>最重要ポイント</b>は太字で強調する。</p>
</header>
```

## 結論カード（verdict）

答え・判断を冒頭で示す文書（調査・障害報告・提案）で使う。文書に 1 つだけ。
`verdict-grid` は対象別のサマリ（例: 対象Aは完了 / 対象Bは未対応）があるときだけ入れる。

```html
<div class="verdict" id="verdict">
  <span class="verdict-label">結論</span>
  <p class="answer">一番伝えたい判断・答えを 2〜4 文で。</p>
  <div class="verdict-grid">
    <div class="verdict-card">
      <h3>対象A <span class="pill ok">対応済み</span></h3>
      <p>対象Aの状態を 1〜2 文で。</p>
    </div>
    <div class="verdict-card">
      <h3>対象B <span class="pill critical">未対応 / 6項目</span></h3>
      <p>対象Bの状態を 1〜2 文で。</p>
    </div>
  </div>
</div>
```

目次からリンクする場合は `<li><a href="#verdict">結論</a></li>` を先頭に置く。

## ピル（pill）

状態・深刻度のラベル。5 種のセマンティクスは固定。**強調目的で流用しない**
（アクセント色と役割を分けることで、色が「意味」を運べる）。

| クラス | 意味 | 例 |
|---|---|---|
| `pill ok` | 完了・問題なし・成功 | 対応済み / PASS |
| `pill critical` | 重大・即対応・失敗 | CRITICAL / ブロッカー |
| `pill high` | 注意・優先度高 | HIGH / 要確認 |
| `pill required` | 必須・主要項目 | REQUIRED / MUST |
| `pill ops` | 運用・情報・中立 | OPS / INFO / 参考 |

```html
<span class="pill critical">CRITICAL</span>
<span class="pill ok">対応済み</span>
```

## セクション（section + h2）

```html
<section id="sec-1">
  <h2><span class="sec-no">1</span>セクション見出し</h2>
  <p>本文。</p>
</section>
```

- `sec-no` の番号は、順序・優先度に意味があるときだけ使う。意味がなければ
  `<h2>見出しだけ</h2>` でよい（番号は情報であって装飾ではない）。
- id は `sec-1`, `sec-2`, ... で目次と一致させる。

## 指摘カード（finding）

課題・指摘・リスク・改善提案の列挙に使う。左ボーダー色 = 深刻度
（`critical` / `high` / `required` / `ops` / `ok`）。

```html
<div class="finding critical" id="f-1">
  <h3><span class="f-no">①</span>指摘のタイトル <span class="pill critical">CRITICAL</span></h3>
  <p>何が問題か。<code>ファイルパス:行</code> など一次情報への参照を含める。</p>
  <p class="fix"><b>対応:</b> どう直すか。参照実装があれば <code>パス</code> を示す。</p>
</div>
```

- `f-no`（① ② …）は優先度・参照用の通し番号。目次のサブ項目からリンクできるよう id を振る。
- `.fix` ボックスは「対応方法」がある場合のみ。所感や補足には使わない。

## テーブル（.table-wrap）

**必ず `.table-wrap` で包む**（横幅が出たときにテーブル内だけスクロールさせ、
ページ全体の横スクロールを防ぐ）。数値・日付・コードが縦に並ぶ列は `td.num`。

```html
<div class="table-wrap">
  <table>
    <thead>
      <tr><th>項目</th><th>内容</th><th>数値</th></tr>
    </thead>
    <tbody>
      <tr><td>行1</td><td>説明はセル内で完結させず本文へ</td><td class="num">42,000</td></tr>
    </tbody>
  </table>
</div>
```

## フロー図（flow）

処理の流れ・時系列・多段パイプラインの表現。`who` = 主体（システム・人・工程）、
`what` = 何が起きるか。`flow-hazard` で問題箇所をマークできる。

```html
<div class="flow-wrap">
  <div class="flow">
    <div class="flow-step">
      <span class="who">主体A</span>
      <span class="what">最初のステップの説明 <span class="flow-hazard">← 問題箇所ならこれ</span></span>
    </div>
    <div class="flow-arrow"><span>↓ 遷移の説明（ジョブ名・イベント名など）</span></div>
    <div class="flow-step">
      <span class="who">主体B</span>
      <span class="what">次のステップの説明</span>
    </div>
  </div>
</div>
```

## 補足（.note）

セクション末尾の脚注レベルの補足。参照ファイルパスの列挙などに向く。

```html
<p class="note">補足: <code>app/models/foo.rb:42</code> を参照。</p>
```

## リスト（ul）

「対応不要と確認できたもの」のような列挙に。各項目は `<b>ラベル:</b> 説明` の形が読みやすい。

```html
<ul>
  <li><b>項目名:</b> 説明文。</li>
</ul>
```

## フッター（footer）

調査対象・日時・主な参照元。読者が一次情報に戻るための導線なので省略しない。

```html
<footer>
  調査対象: リポジトリ名 (ブランチ, 日付時点) · 主な参照: PR #1234 / path/to/file
</footer>
```

## 目次（toc）— サブ項目の例

指摘カードなど小項目にジャンプさせたいときはネストした `<ol>` を使う。

```html
<nav class="toc" aria-label="目次">
  <p class="toc-title">目次</p>
  <ol>
    <li><a href="#verdict">結論</a></li>
    <li>
      <a href="#sec-1">1. 指摘一覧</a>
      <ol>
        <li><a href="#f-1">① 指摘タイトル（短縮形）</a></li>
        <li><a href="#f-2">② 指摘タイトル（短縮形）</a></li>
      </ol>
    </li>
    <li><a href="#sec-2">2. チェックリスト</a></li>
  </ol>
</nav>
```
