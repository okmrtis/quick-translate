# QuickTranslate の仕組みと確かめ方

## ファイル

| ファイル | 役割 |
| --- | --- |
| `QuickTranslate.ahk` | 常駐プログラム（AutoHotkey v2）。Ctrl+C+C を見張り、Claude Code CLI に翻訳を頼み、窓を出す |
| `QuickTranslatePanel.html` | 翻訳の窓の中身。WebView2 で表示する |
| `WebView2Loader.dll` | Microsoft の WebView2 SDK 1.0.3485.44 の読み込み部品（Microsoft 署名、無改変） |
| `QuickTranslate.ico` | アイコン |
| `manifest.json` | 版と、各ファイル・AutoHotkey 配布物の SHA-256 |
| `install.ps1` / `setup.ps1` / `uninstall.ps1` | 導入・1行セットアップ・削除 |
| `Install-QuickTranslateStartup.ps1` | サインイン時に起動するタスクの登録（`install.ps1` から呼ばれる） |
| `Test-QuickTranslateStartup.ps1` | 導入状態の検証（画面操作なし） |

## 翻訳の流れ

1. 同じ窓で Ctrl+C+C を押す（2回目の Ctrl+C が 650 ms 以内）と、Windows のクリップボード変更通知か、1回目の時点から変わったクリップボードの連番（`GetClipboardSequenceNumber`）でコピーを確かめ（最大 1.5 秒待つ）、その文字を翻訳します。1回だけのときは何もしません。`events.log` の `first-copy-ready-gap<ms>`・`copy-change-timeout-gap<ms>`・`double-copy-recognized-gap<ms>-<notice|seq>` には、前の Ctrl+C からの間隔（ミリ秒）と確かめた方法が付きます。
2. 翻訳は、サインイン済みの Claude Code CLI を print モード（`-p --input-format stream-json --output-format stream-json --include-partial-messages`）で使います。ユーザー設定・フック・ツール・MCP は読み込ませません。
3. 起動を待たずに済むよう、翻訳待ちの CLI を1つだけ先に起動しておき（約 150 MB）、1回の翻訳ごとに使い捨てます。続けて使っても会話がたまって遅くなることはありません。待機中の CLI は3時間ごとに入れ替えます。
4. CLI はすべて常駐と同じ Windows のジョブに入れ、常駐が終わると必ず一緒に終わります。原文は CLI の標準入力に渡すだけで、出力を受け取る一時ファイル（`work\*.jsonl`）は読んだ直後に消します。
5. 訳が30秒（`StallMs`）たっても1文字も届かないときは、その依頼を打ち切り、待機中の CLI で1回だけやり直します。2分以内に終わらない翻訳は止めて知らせます。

答えは次の形で返してもらい、窓で組み立てます。

```
<全文訳>
---
原文の語句 ｜ その語句の訳
…
```

## 翻訳の窓

- 起動の3秒後に、窓を画面に出さずに準備しておきます（GPU を使わない描画で約 90 MB）。翻訳のたびに同じ窓を使い回すので、すぐ開きます。
- マウスのある画面の作業領域の右下に、幅 560・高さ 300（拡大率 100% での画素数）で開きます。訳が長いと、下端を保ったまま上へ伸びます（高さ 760 か作業領域の上端まで）。
- 窓は Windows の普通の窓（常に手前ではない、最大化・最小化・大きさ変更のできる窓）として登録し、タイトルバーの部分だけを WebView2 のページに渡しています（`WM_NCCALCSIZE`）。そのため、Windows の窓操作とスナップアシストがそのまま使えます。
- 開いた直後にコピー元のアプリが前面を取り返すことがあるため、0.25 秒後と 0.9 秒後にもう一度確かめ、マウスを押していなければ前面へ戻します（`events.log` の `panel-front-restored-<回>`）。前面にある窓の入力とはつなぎません（`AttachThreadInput` を使いません）。Chrome が前面のときにつなぐと常駐が固まり、窓が「翻訳中」のまま止まったためです。
- 窓は、翻訳を始めてから 150 秒たっても結果もエラーも届かないとき、「翻訳の結果が届きませんでした」と表示します（常駐は2分以内に必ず結果かエラーを返すため、それを過ぎたら常駐が応答していないと判断します）。
- 強調色はティール（明るい表示で `#0d8a80`、暗い表示で `#22b3a5`）です。アイコンの「あ」の吹き出しも同じ系統の `#0d9488` です。
- 窓には専用のアプリ ID（`okmrtis.QuickTranslate`）・名前・アイコンを付け、タスクバーで AutoHotkey としてまとめられず QuickTranslate のアイコンで出るようにしています。
- 画面ごとの拡大率で描くので、拡大率の違う画面へ動かしても文字はぼやけません。
- 窓とページは JSON のメッセージでやり取りします。常駐からは `start`・CLI の出力行（文字の断片と最終結果）・`revising`・`error`・`close`・`max` を送ります。ページからは `ready`・`size:<高さ>`・`copy:<文字>`・`revise:<JSON>`・`maximize`・`keep-open`・`hide` を返します。
- 訳し直しは、選んだ文字・コメント・原文・現在の訳を常駐に送り、同じ形の答え全体をもう一度受け取ります。前の訳に無い文には印を付けます。
- WebView2 を起動できないときは、Windows の古い Web ブラウザー部品の窓で完成した訳を表示します。

## 記録

`events.log` には、時刻・プロセス番号・状態コードだけを書きます（原文や訳は書きません）。128 KiB を超えると1世代だけ残します。予期しないエラーは AutoHotkey のエラー画面を出さず、`unexpected-error-…` として記録します。

## 確かめ方

スクリプトは `#Warn All, StdOut` で読み込み時の警告を標準出力に出します。`Test-QuickTranslateStartup.ps1` は、タスクの設定、常駐が1つだけ動いていること、各ファイルの SHA-256、WebView2Loader.dll の Microsoft 署名、導入済みスクリプトが警告なしで読み込めることを、画面操作なしで確かめます。

自己テストは、常駐を置き換えないよう、導入先とは別のフォルダーにコピーした `QuickTranslate.ahk`（と `QuickTranslatePanel.html`・`WebView2Loader.dll`）で実行します。`/ErrorStdOut=UTF-8` を付けると、エラーが画面に出ません。

| コマンド | 確かめること | 画面 |
| --- | --- | --- |
| `--self-test-cli <入力> <出力> [待機ms]` | CLI での翻訳 | 出さない |
| `--self-test-panel <出力> <答え> [原文]` | 答えを3回に分けて窓に流し込み、届くたびに描いたあとの表示内容 | 出さない |
| `--self-test-translate <入力> <出力>` | Ctrl+C の後と同じ処理で、翻訳から窓の中身まで（実際の Claude を使う） | 出さない |
| `--self-test-revise <入力> <出力>` | 上に続けて、最初の文の訳し直し | 出さない |
| `--self-test-place <出力>` | 右下の配置、タイトルバーを外した Windows の窓であること、常に手前でないこと | 出さない |
| `--self-test-keys <出力>` | Win+↑・Win+↓・F11・Win+→・Ctrl+W を実際に送る | **出す** |

`--self-test-keys` は窓を実際に画面に出し、キーを送ります。キーは、そのたびに翻訳の窓が前面にあることを確かめてから送ります。ほかの窓が前面になったら、そこで止めます。窓と同じプログラムから送ったキーでは、Windows がスナップアシストを出しません。そのため、スナップアシストはこの試験では確かめません（常に手前の窓にはスナップアシストが出ないので、`--self-test-place` が常に手前でないことを確かめます）。

## ファイルを変えたとき

`manifest.json` の `script_sha256`・`panel_sha256` などを、変えたファイルの SHA-256 に合わせます。`install.ps1` と検証スクリプトは、この値と照合します。
