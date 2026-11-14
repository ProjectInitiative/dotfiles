# CCU ファームウェア

(英語版: [README.md](README.md))

カメラの CCU(Camera Control Unit)は NVIDIA の署名付きファームウェア
`nvCCU.img` で動きます。これは NVIDIA の所有物なので、このリポジトリには
**含めていません**。各自が、自分のマシンに付属していた Windows から
コピーしてください。SoC の Root of Trust は NVIDIA の署名付きイメージしか
起動しないので、どのみちこのファームウェア以外は動きません。

## 抜き出す

`extract-from-windows.sh` は Windows パーティションを読み取り専用でマウント
(またはマウント済みのものを使用)し、ドライバストアから最新の
`nvccu.inf_arm64_*` パッケージを探して、`nvCCU.img` をスクリプトの隣に
コピーします。

```sh
sudo ./extract-from-windows.sh                  # Windows パーティションを自動検出
sudo ./extract-from-windows.sh /dev/nvme0n1p3   # パーティションを指定
./extract-from-windows.sh /mnt/win              # マウント済みの Windows ルートを指定
```

## インストール

```sh
sudo install -Dm644 nvCCU.img /lib/firmware/nvidia/n1x/nvCCU.img
```

Root of Trust のデバイス(ACPI `NVDA8600`)が probe されたときに、
`surface_ccu_boot` がこのパスから読み込みます。

このファイルは複数の SoC 向けのイメージをまとめたコンテナで、ドライバは
`mt8991` 向けのものを使います。
