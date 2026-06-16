# Phase 4 Infra Tuning

MySQL / nginx / memcached / Redis の定番設定を、単体差分で段階評価する。

## Read First

- `$TOOL_REPO/references/goal-common.md`
- `$TOOL_REPO/references/agent-rules.md`
- `$TOOL_REPO/references/phase-boundaries.md`

## Preconditions

- ツールリポジトリで `source scripts/env.sh` して、`TOOL_REPO`・`ISUCON_RUNTIME`・`DOCKER_COMPOSE_DIR`・`DOCKER_COMPOSE_FILE_ARGS`・`DOCKER_MYSQL_SERVICE`・`NGINX_CONF_HOST_DIR`・`BENCH_CMD`・`REBUILD_CMD` を確認する。
- 変更は1テーマずつ行い、複数設定をまとめて入れない。
- 悪化、効果不明なら戻す。
- fail が出た場合は `$TOOL_REPO/references/goal-common.md` の Failure Diagnosis に従う。
- 採用/却下理由とスコアを `$TOOL_REPO/reports/infra-tuning.md` に記録する。
- Phase 4 では分析用ログを維持する。

## Baseline

1. `$TOOL_REPO/scripts/bench-locked.sh --rebuild`
2. `$TOOL_REPO/scripts/analyze.sh`
3. `$TOOL_REPO/scripts/score-log.sh <score> "infra baseline"`
4. MySQL の現状値を確認する。

   ```bash
   docker compose $DOCKER_COMPOSE_FILE_ARGS exec -T "$DOCKER_MYSQL_SERVICE" \
     mysql -u"$DB_ADMIN_USER" -p"$DB_ADMIN_PASS" \
     -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size'; SHOW VARIABLES LIKE 'innodb_flush_log_at_trx_commit'; SHOW VARIABLES LIKE 'sync_binlog';"
   ```

## Candidates

1. MySQL buffer pool を段階評価する。
   - Docker 環境では `$DOCKER_COMPOSE_DIR/etc/mysql/20-buffer-pool.cnf` に `$TOOL_REPO/templates/mysql-buffer-pool.cnf` を `<BUFFER_POOL_SIZE>` 置換して配置する。
   - systemd + local MySQL では `/etc/mysql/conf.d/20-buffer-pool.cnf` または `/etc/my.cnf.d/20-buffer-pool.cnf` に配置する。
   - `256M`、`512M`、余裕があれば `768M` を単体評価する。
   - 最もスコアが良い値だけ残し、他は戻す。
2. MySQL durability relaxed 設定を単体評価する。
   - `$TOOL_REPO/templates/mysql-durability-relaxed.cnf` を `21-durability-relaxed.cnf` として配置する。
   - `innodb_flush_log_at_trx_commit=2` と `sync_binlog=0` はクラッシュ耐久性を緩めるため、競技中のベンチ用途として採否を明記する。
   - 改善しなければ削除して戻す。
3. MySQL connection/cache 系を単体評価する。
   - `$TOOL_REPO/templates/mysql-connection-cache.cnf` を `22-connection-cache.cnf` として配置する。
   - 改善しなければ削除して戻す。
4. nginx upstream keepalive を単体評価する。
   - `$TOOL_REPO/templates/nginx-upstream-keepalive.conf` を参考に、既存 nginx 設定へ upstream と `proxy_http_version` / `Connection` ヘッダだけを差分適用する。
   - Docker 環境では `$NGINX_CONF_HOST_DIR` 配下の既存 server 設定を編集する。
   - systemd 環境では `sudo nginx -t`、Docker 環境では `docker compose $DOCKER_COMPOSE_FILE_ARGS exec -T "$DOCKER_NGINX_SERVICE" nginx -t` で設定テストしてからベンチする。
   - 改善しなければ差分を戻す。
5. memcached 設定を必要な場合だけ評価する。
   - memcached がセッションまたはキャッシュ用途で使われている場合、`$TOOL_REPO/templates/memcached-competition.command` を参考に `-m 256 -c 4096 -t 2` を単体評価する。
   - 正データを保持している場合は実施しない。
6. Redis 設定を Redis 採用環境で必要な場合だけ評価する。
   - Redis がキャッシュ用途なら `$TOOL_REPO/templates/redis-cache.conf` を参考に persistence off と maxmemory-policy を評価する。
   - Redis が正データの場合、`save ""` と `appendonly no` は使わない。

## Final-Prep Handoff

Phase 6 に送る最終整備候補を `$TOOL_REPO/reports/infra-tuning.md` に記録する。

- MySQL slow query log off
- nginx access_log off
- pprof 削除
- 分析用 override の整理

これらは Phase 4 では実施しない。

## Report

`$TOOL_REPO/reports/infra-tuning.md` に以下をまとめる:

- baseline score
- 各候補の設定差分
- score
- pass / fail
- 採用 / 却下
- 最終採用設定

## Forbidden

- 複数テーマをまとめて評価すること。
- MySQL slow query log off、nginx access_log off、pprof 削除、分析用 override 整理など Phase 6 の最終提出作業を実施すること。
- 分析用ログ設定と最終ログ抑制設定を同じ測定として扱うこと。
