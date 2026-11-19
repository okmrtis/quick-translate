# QuickTranslate

**Ctrl+C を2回押すだけで、どのアプリの英文もその場で日本語に。**

- 文章を選んで **Ctrl+C を2回**。画面の右下にすぐ翻訳の窓が開き、訳が書かれるそばから表示されます。
- 全文訳の下には、原文を語句ごとに区切り、その下にそれぞれの意味を添えた**対訳**が並びます。
- 訳の一部を選ぶと、すぐ下に入力欄が開きます。直し方を書いて **Enter** を押すと、その箇所を中心に訳し直します（前後も必要に応じて直します）。
- 翻訳の窓は Windows の普通の窓として扱われます。**Win+←/→** で画面の半分に寄せる、**Win+↑** で最大化、**Esc / Ctrl+W** で閉じる、などがそのまま使えます。
- 翻訳には [Claude Code](https://docs.claude.com/en/docs/claude-code/overview)（Claude のコマンドライン版）を使います。API キーは要りません。サインインした Claude のアカウントで動きます。

## 必要なもの

- Windows 10 / 11（64 ビット）
- **Claude Code**：PowerShell で次を実行してインストールし、`claude` を一度起動してサインインしておきます。Claude Code が使えるプラン（Pro・Max など）が必要です。

  ```powershell
  irm https://claude.ai/install.ps1 | iex
  ```

- Microsoft Edge WebView2 ランタイム（Windows 11 には最初から入っています。無い場合は [こちら](https://developer.microsoft.com/microsoft-edge/webview2/)）

## インストール

PowerShell で次の1行を実行します。管理者権限は要りません。

```powershell
irm https://raw.githubusercontent.com/okmrtis/quick-translate/main/setup.ps1 | iex
```

ZIP をダウンロードした場合は、展開したフォルダーで次を実行します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

インストールすると次のようになります。

- 本体は `%LOCALAPPDATA%\Programs\QuickTranslate` に入ります。
- サインインすると自動で起動するタスク「QuickTranslate」が登録され、その場で起動します。
- 動作に使う [AutoHotkey](https://www.autohotkey.com/) v2.0.28 は、公式の GitHub リリースから取得し、SHA-256 を確かめてから使います。

## 使い方

1. どのアプリでも、訳したい文章を選んで **Ctrl+C を2回**（0.65 秒以内）押します。1回だけ押したときは、いつもどおりのコピーです。
2. 右下に窓が開き、「翻訳中」の表示のあと、訳が流れ込みます。全文訳の下に対訳が並びます。
3. 訳を直したいときは、直したい部分を選び、すぐ下に開いた欄に直し方を書いて **Enter** を押します（書かずに Enter だけでも可）。変わった文には数秒だけ印が付きます。

| 操作 | キー |
| --- | --- |
| 閉じる | Esc / Ctrl+W / 右上の × |
| 訳をコピー | 右上のコピーのアイコン |
| 最大化・元に戻す | F11 / Win+↑・Win+↓ / 右上の広げるアイコン |
| 画面の半分に寄せる | Win+← / Win+→（反対側にほかの窓の候補が出ます） |
| 常駐を終了する | Ctrl+Alt+Shift+F12 |

## 設定（任意）

インストール先の `settings.ini`（UTF-16 LE で保存）に書くと変えられます。

```ini
[Cli]
; Claude Code の場所（既定は %USERPROFILE%\.local\bin\claude.exe）
Executable=C:\path\to\claude.exe
; 使うモデル（既定は claude-sonnet-5-5）
Model=claude-sonnet-5-5
; 訳が1文字も届かないとき、別の CLI でやり直すまでの時間（ミリ秒）
StallMs=30000
```

## プライバシー

- 選んだ文章は、あなたの Claude Code を通して Anthropic に送られ、翻訳されます。ほかの送り先はありません。
- 原文や訳はファイルに残しません。CLI の出力を受け取る一時ファイルは、読んだ直後に消します。`events.log` には時刻と状態だけを記録します。
- 翻訳の窓はローカルのページだけを表示し、表示部品の補助的な通信（SmartScreen など）は止めています。

## アンインストール

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\QuickTranslate\uninstall.ps1"
```

## しくみ

AutoHotkey v2 の常駐プログラムが Ctrl+C の2回押しを見張り、待機させておいた Claude Code CLI に翻訳を頼みます。答えは少しずつ受け取って、Microsoft Edge WebView2 で描いた窓に流し込みます。詳しくは [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) を見てください。

## ライセンス

[MIT](LICENSE)。

同梱・利用しているもの：

- `WebView2Loader.dll`：Microsoft の WebView2 SDK に含まれる、Microsoft 署名のファイルをそのまま同梱しています（BSD 形式の許諾。[WebView2Loader-LICENSE.txt](WebView2Loader-LICENSE.txt)）。
- AutoHotkey：同梱していません。インストール時に公式リリースから取得します（GPL v2）。

QuickTranslate は個人のプロジェクトで、Anthropic・Microsoft・AutoHotkey とは関係ありません。

---

## English

**Select text in any Windows app and press Ctrl+C twice — a panel opens in the bottom-right corner and streams a Japanese translation.**

- Below the full translation, the original is split into short phrases with each phrase's meaning under it.
- Select part of the translation, type how to change it (optional) and press Enter to revise it in place.
- The panel is an ordinary Windows window: Win+Left/Right snapping with Snap Assist, Win+Up/Down, Esc / Ctrl+W to close.
- Translation runs through your signed-in [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) CLI (no API key). The panel UI is in Japanese and the target language is Japanese.

**Requirements:** 64-bit Windows 10/11, Claude Code (`irm https://claude.ai/install.ps1 | iex`, then run `claude` once to sign in), Microsoft Edge WebView2 Runtime.

**Install** (no admin rights):

```powershell
irm https://raw.githubusercontent.com/okmrtis/quick-translate/main/setup.ps1 | iex
```

**Uninstall:** run `uninstall.ps1` in `%LOCALAPPDATA%\Programs\QuickTranslate`.

MIT licensed. Not affiliated with Anthropic, Microsoft or AutoHotkey.
