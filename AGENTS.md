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

- `build-aosp.sh` と `run-aosp.sh` の処理は Python（`src/host/aosp_build/`）で実装している。コンテナ内のタスク（`src/container/start.sh` など）、`make-image.sh` などは bash。
- `src/` は、実行時にどこで実行・読み込みされるかで分ける。テストからの参照は分類に数えない（テストはどの場所のファイルも読んでよい）。
  - `src/host/`: ホストだけ。コンテナには渡さない。
  - `src/container/`: コンテナ内だけ。
  - `src/common/`: ホストとコンテナの両方（パッチなど）。
  - コンテナには `src/container/` と `src/common/` だけをマウントし、`/tmp/src/container/`・`/tmp/src/common/` にコピーする。`container/` と `common/` のファイルは、リポジトリ上と同じ相対パス（`container/` から `$SCRIPTDIR/../common/...`）で参照し合う。絶対パス（`/tmp/src/...`）は `host.py` が組み立てるコンテナのコマンドだけで使う。
  - `container/`・`common/` から `host/` は参照しない（Python では `aosp_build` を import しない）。`host/` は `container/` のファイルを実行・読み込みしない（`common/` は読んでよい）。
  - 利用者が直接実行するツールはリポジトリのルートに置く。`src/` は内部の実装とする。開発者だけが使う保守用ツール（`src/host/make_patch.sh`）は実行場所に従って `src/` に置く。
- 利用者が直接実行する可能性のあるスクリプトは、Python で実装する場合も bash のラッパーとし、拡張子を変えない。ラッパーは python3 を exec するだけとする。
- `src/host/` の Python は Python 3.8 以上で動き、外部ライブラリに依存しない（ホストの要件）。`src/container/`・`src/common/` の Python はイメージの Python（3.8）の標準ライブラリだけを使う（イメージを変更しないため）。`TEST_IN_IMAGE=1 bash tests/test-python.sh` または `uv run --python 3.8 bash tests/test-python.sh` で確認できる。テストの import パスは `PYTHONPATH=src/host:src/common`。
- パラメータを追加するときは `src/host/aosp_build/fields.py` の `FIELDS` と `build-aosp.example.ini` を更新する。
- 設定ファイルは INI（標準ライブラリの `configparser`）とし、外部ライブラリに依存しない。
- バージョンごとのビルド設定（ブランチ、lunch、make ターゲット、環境変数など）は `src/host/aosp_build/versions/android_<version>.py` に、組み合わせ（platform / form factor）ごとの表として書く。`resolve()` にバージョンや組み合わせの分岐を足さない。コンテナのタスクは、ホストが書いた `build-config-*.json` を `src/container/config_env.py` 経由で読む。AOSP のビルドに渡す環境変数は `build_env`（`Kind.env` / `Variant.env`）に足せばコンテナでも export される。`ResolvedConfig` にキーを足すときは `src/container/config_env.py` の対応表も更新する。
