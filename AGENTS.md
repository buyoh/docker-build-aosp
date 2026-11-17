# build-aosp-rpi

このツール群は、主に以下の用途でAOSPをビルドするためのものです。

- AOSPをビルドし、Raspberry Pi 4 上で動かす
- 必要に応じてRaspberry Pi 向けパッチを無効化し、エミュレータ(x64(上で動かせるようにする
- Android TV向けのビルドを行える。
- Android 14 では TV / スマートフォン / 車載を切り替えてビルドできる（`--form-factor`）。非 RPi の成果物は cuttlefish・Android Emulator でホスト上に起動できる（`run-aosp.sh`）。

## 想定

- Docker 環境は rootless とする。root docker も実装としては残っているが、deprecated とされている。

## Agent によるデバッグについて

動作確認はディスク容量の観点から、なるべく行わないようにする。必要な場合、`./local/aosp-std/` のディレクトリで行う。これはシンボリックリンクであり、実体は別の場所にある。

## 実装について

- `build-aosp.sh` と `run-aosp.sh` の処理は Python（`src/aosp_build/`）で実装している。コンテナ内のタスク（`src/start.sh` など）、`make-image.sh` などは bash。
- 利用者が直接実行する可能性のあるスクリプトは、Python で実装する場合も bash のラッパーとし、拡張子を変えない。ラッパーは python3 を exec するだけとする。
- `src/` の Python は Docker イメージの Python（3.8）でも動くようにする。`TEST_IN_IMAGE=1 bash tests/test-python.sh` または `uv run --python 3.8 bash tests/test-python.sh` で確認できる。
- パラメータを追加するときは `src/aosp_build/fields.py` の `FIELDS` と `build-aosp.example.ini` を更新する。
- 設定ファイルは INI（標準ライブラリの `configparser`）とし、外部ライブラリに依存しない。
