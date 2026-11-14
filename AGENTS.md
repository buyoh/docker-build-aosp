# build-aosp-rpi

このツール群は、主に以下の用途でAOSPをビルドするためのものです。

- AOSPをビルドし、Raspberry Pi 4 上で動かす
- 必要に応じてRaspberry Pi 向けパッチを無効化し、エミュレータ(x64(上で動かせるようにする
- Android TV向けのビルドを行える。

## 想定

- Docker 環境は rootless とする。root docker も実装としては残っているが、deprecated とされている。

## Agent によるデバッグについて

動作確認はディスク容量の観点から、なるべく行わないようにする。必要な場合、`./local/aosp-std/` のディレクトリで行う。これはシンボリックリンクであり、実体は別の場所にある。
