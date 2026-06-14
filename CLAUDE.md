# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

このリポジトリはISUCON（Webパフォーマンスチューニングコンテスト）向けのスキル・スクリプト集。
競技本番で再利用できる汎用的な最適化手順、ツール、テンプレートを提供する。

テスト環境として `~/private-isu` を使用する。スキルやスクリプトの動作検証・性能計測はすべてそこで行う。

## Test Environment: ~/private-isu

`~/private-isu` はISUCONの練習環境（SNS風Webアプリ）。

### 起動

```bash
cd ~/private-isu/webapp
docker compose up -d
```

### ベンチマーク実行

```bash
cd ~/private-isu/benchmarker
make  # 初回のみビルド
./bin/benchmarker -t "http://localhost:8080" -u ./userdata
```

スコア例: `{"pass":true,"score":1710,"success":1434,"fail":0,"messages":[]}`

### 初期化

```bash
cd ~/private-isu
make init  # dump.sql.bz2 と画像ファイルをダウンロード
```

### アーキテクチャ

- MySQL 8.4（users / posts / comments テーブル）
- Memcached（セッション管理）
- Nginx（リバースプロキシ）
- 実装言語：Ruby（デフォルト）/ Go / PHP / Python / Node.js

### 主な性能ボトルネック（検証対象）

- 画像をDBのBLOBとして保存
- タイムライン生成のN+1クエリ
- DBインデックス未設定
- セッションをDBに保存

## Repository Structure

```
/                    # スキル・スクリプト置き場（今後追加予定）
~/private-isu/       # テスト環境（このリポジトリ外）
```

## Development Flow

1. スキル・スクリプトを本リポジトリに追加・修正する
2. `~/private-isu` に適用して動作確認する
3. ベンチマーカーでスコアを計測して効果を検証する
4. 結果をコミットに記録する

## Environment Variables (private-isu)

| 変数名 | 説明 |
|--------|------|
| `ISUCONP_DB_HOST` | DBホスト |
| `ISUCONP_DB_PORT` | DBポート（3306） |
| `ISUCONP_DB_USER` | DBユーザー |
| `ISUCONP_DB_PASSWORD` | DBパスワード |
| `ISUCONP_DB_NAME` | DB名（isuconp） |
| `ISUCONP_MEMCACHED_ADDRESS` | Memcachedアドレス |
