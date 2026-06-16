# Phase 6 Final Prep

最終提出用にサーバー状態を整備し、再起動後も採用構成でベンチが通ることを確認する。

## Read First

- `$TOOL_REPO/references/goal-common.md`
- `$TOOL_REPO/references/agent-rules.md`
- `$TOOL_REPO/references/phase-boundaries.md`

## Preconditions

- ツールリポジトリで `source scripts/env.sh` して、`TOOL_REPO`・`ISUCON_RUNTIME`・`ISUCON_WEBAPP_DIR`・`BENCH_CMD`・`REBUILD_CMD` を確認する。
- これ以降は新規チューニングを追加しない。
- 採用済み設定の固定、不要設定の無効化、再現性確認だけを行う。
- benchmark は必ず1つだけ実行する。
- 最終整備前後のスコアを `$TOOL_REPO/scripts/score-log.sh` で記録する。

## Procedure

1. 採用済み変更を確認する。
   - app リポジトリの branch / commit / diff を確認する。
   - 採用した nginx / MySQL / Redis / memcached / systemd / Docker Compose 設定を一覧化する。
   - DB が RDS / Aurora の場合は、採用した RDS パラメータグループの変更分（`innodb_*` 等）も一覧に含める。
   - 未採用・評価途中の設定ファイルを残していないか確認する。
2. 分析用設定を外す。
   - pprof 用ポート公開、`net/http/pprof`、pprof goroutine は最終スコアに不要なら外す。
   - MySQL slow query log は最終測定用に off へ戻すか、少なくとも `long_query_time=0` をやめる。
     - ローカル / Docker MySQL: `.cnf` または `SET GLOBAL` で戻す。
     - RDS / Aurora: ローカル設定ではなくパラメータグループで戻す（`slow_query_log=0`、
       または `long_query_time` をデフォルトへ。`bash $TOOL_REPO/scripts/setup-rds.sh --aws-cli` で
       入れた場合は同じパラメータグループを戻す）。加えて `mysql.slow_log` テーブルに蓄積したデータを
       `CALL mysql.rds_rotate_slow_log;`（または `ROTATE_RDS_SLOW_LOG=1 bash $TOOL_REPO/scripts/analyze-rds.sh`）で掃除する。
   - nginx access log は最終測定用に off または軽量化する。
   - Docker Compose 環境では、分析専用 override に最終構成が依存していないか確認する。
3. 起動経路を固定する。
   - systemd 環境では `systemctl cat <service>` を確認する。
   - Docker Compose 環境では、最終ベンチで使う compose ファイル列を明確にする。
   - RDS / Aurora 環境では、採用したパラメータグループ設定が反映済みか確認する
     （`ApplyMethod=pending-reboot` の項目は DB 再起動が必要。再起動後も値が保持される）。
   - 最終スコアに必要な設定は通常起動で読まれる場所に置く。
   - nginx / app / DB / cache を再起動しても採用設定が残ることを確認する。
4. データ初期化と静的ファイルを確認する。
   - `/initialize` 後に画像・アップロードファイル・生成済み静的ファイルが期待位置に存在するか確認する。
   - app 複数台構成の場合、画像保存先やセッション保存先が全 app で共有されているか確認する。
   - nginx 直配信している path が、initialize 後も stale file を返さないことを確認する。
5. 最終ベンチ相当で測定する。
   - 採用済み構成だけで rebuild / restart する。
   - `$TOOL_REPO/scripts/bench-locked.sh --rebuild`
   - pass / score / messages を確認し、`$TOOL_REPO/scripts/score-log.sh <score> "final server prep"` で記録する。
   - fail があればログから原因を特定し、最終整備の変更を戻して再測定する。
6. 再起動後の再現性を確認する。
   - 競技ルール上許される範囲で、サービス再起動または Docker Compose の `up -d` を実行する。
   - 起動後に nginx / app / DB / cache の状態を確認する。
   - もう一度ベンチを実行し、pass とスコア水準が維持されることを確認する。
7. `$TOOL_REPO/reports/final-prep.md` に最終メモを残す。

## Report

`$TOOL_REPO/reports/final-prep.md` に以下をまとめる:

- 最終 app commit
- 最終 compose / systemd / nginx / MySQL / cache 設定
- 外した分析用設定
- 最終ベンチスコア
- 再起動後ベンチスコア
- 既知のリスク

## Forbidden

- 提出直前に未評価の最適化を追加すること。
- pprof や slow query `long_query_time=0` を最終構成に残したまま、理由なく提出すること。
- 分析用 override にしか存在しない設定へ最終構成を依存させること。
- pass していない構成を最終構成として扱うこと。
