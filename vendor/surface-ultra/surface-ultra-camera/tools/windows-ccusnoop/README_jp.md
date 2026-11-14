# ccusnoop:Windows でカメラの設定を採取する

(英語版: [README.md](README.md))

`kernel/` のレジスタ表を得るために使った、**読み取り専用**の小さな Windows
(arm64)カーネルドライバです。Windows のカメラアプリが映像を出している間に、
次の2つを記録します。

1. CCU の RPC メールボックス(物理アドレス `0x3C0BC0C8` と、2つ目の
   メールボックス `0x3C0CC0C8`)をポーリングし、Windows が送る全コマンド
   (feature、コマンド ID、長さ、ステータス、ペイロード)を記録する
2. 1秒ごとに、CPU から直接見えるカメラのブロックをダンプする:rxana、D-PHY、
   mac_top、mac_csi、seninf-top/async(保護されていて 0 に見える)、
   全14個の outmux、camsv a/b(DMA ブロックを含む)

ログはドライバを停止したときに `C:\ccusnoop.log` に書き出されます。読むだけで、
ハードウェアには一切書き込みません。

他の機種やセンサーへの移植、またはレジスタ表の再確認をするときだけ必要です。
実行にはテスト署名モードが必要で、有効にしている間はその Windows の
セキュリティが下がります。

## ビルド

Windows 11 arm64 に Visual Studio 2026、Windows Driver Kit、
「C++ ARM64 build tools」コンポーネントを入れます。空の WDM ドライバ
プロジェクトを作って `ccusnoop.c` を追加し Release/ARM64 でビルドするか、
WDK の開発者プロンプトで付属のプロジェクトをビルドします。

```
msbuild ccusnoop.vcxproj /p:Configuration=Release /p:Platform=ARM64
```

## テスト署名を有効にする

管理者プロンプトで実行し、再起動します(デスクトップに "Test Mode" と出ます)。

```
bcdedit /set testsigning on
```

それでも未署名ドライバが読み込めない場合は、自己署名します。

```
makecert -r -ss PrivateCertStore -n CN=ccusnoopTest ccusnoopTest.cer
signtool sign /s PrivateCertStore /n ccusnoopTest /fd sha256 ccusnoop.sys
certmgr /add ccusnoopTest.cer /s /r localMachine root
```

## 採取

```
sc create ccusnoop type= kernel binPath= C:\path\to\ccusnoop.sys
sc start ccusnoop
```

Windows のカメラアプリを開いてプレビューを数秒出します(解像度を変えても
構いません)。プレビューを出したまま、次を実行します。

```
sc stop ccusnoop
sc delete ccusnoop
```

ストリーム中に止めると、最後のダンプがストリーム中の状態になります。
ポーリングで CPU コアを1つ使い続けるので、終わったら止めてください。
テスト署名も元に戻してください(`bcdedit /set testsigning off`)。

## ログの読み方

メールボックスの行は次の形式です。

```
mb0 w=<連番> ft=<feature> cmd=0x<ID> len=<バイト数> st=0x<ステータス> pl: <ペイロード>
```

`ft=4` が seninf です。1回のストリーム開始は、最初の `ft=1 cmd=0xd` から、
ペイロード `{1, 1}` の `ft=4 cmd=0x2`(MSG_SENINF_SET_STREAM の on)まで
です。レジスタダンプは `=== DUMP #n ===` で始まり、全部 0 の行は省略されます。
