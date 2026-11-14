# build-aosp-rpi

このツール群は、主に以下の用途でAOSPをビルドするためのものです。

- AOSPをビルドし、Raspberry Pi 4 上で動かす
- 必要に応じてRaspberry Pi 向けパッチを無効化し、エミュレータ(x64(上で動かせるようにする
- Android TV向けのビルドを行える。

## 想定

- Docker 環境は rootless とする。root docker も実装としては残っているが、deprecated とされている。

## Agent によるデバッグについて

動作確認はディスク容量の観点から、なるべく行わないようにする。必要な場合、`./local/aosp-std/` のディレクトリで行う。これはシンボリックリンクであり、実体は別の場所にある。

## 実装について

- `build-aosp.sh` の処理は Python（`src/aosp_build/`）で実装している。コンテナ内のタスク（`src/start.sh` など）、`make-image.sh` などは bash。
- 利用者が直接実行する可能性のあるスクリプトは、Python で実装する場合も bash のラッパーとし、拡張子を変えない。ラッパーは python3 を exec するだけとする。
- `src/` の Python は Docker イメージの Python（3.8）でも動くようにする。`TEST_IN_IMAGE=1 bash tests/test-python.sh` または `uv run --python 3.8 --with pyyaml bash tests/test-python.sh` で確認できる。
- パラメータを追加するときは `src/aosp_build/fields.py` の `FIELDS` と `build-aosp.example.yaml` を更新する。
