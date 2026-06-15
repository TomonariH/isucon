# isucon

ISUCON 競技向けスクリプト・スキル集。  
`~/private-isu` を試験環境として動作確認している。

## ディレクトリ構成

```
scripts/
  install-claude.sh # Claude Code CLI をインストールする
  setup-tools.sh    # alp / pt-query-digest インストール（分析実行サーバー）
  setup-nginx.sh    # nginx LTSV アクセスログ設定（nginx サーバー）
  setup-mysql.sh    # MySQL スロークエリログ設定（DB サーバー、ローカル MySQL 用）
  setup-app.sh      # git init / reports ディレクトリ作成（アプリサーバー）
  setup-docker.sh   # Docker Compose 環境向けセットアップ（ログ expose・nginx LTSV・MySQL slow log）
  setup-rds.sh      # RDS 環境向けセットアップ（MySQL が AWS RDS / Aurora の場合）
  lib.sh            # 共通環境検出ライブラリ（OS / arch / MySQL サービス名など）
  analyze.sh        # ベンチ後に毎回実行する計測・レポート生成（H2O 自動検出）
  analyze-rds.sh    # RDS 環境向け分析（mysql.slow_log テーブル対応）
  score-log.sh      # スコアを reports/scores.md に記録
templates/
  nginx-ltsv.conf           # nginx LTSV アクセスログ設定
  mysql-slow.cnf            # MySQL スロークエリログ設定
  nginx-staticfile.conf     # 静的ファイル直接配信設定（画像 DB 脱却後に使用）
  nginx-upstream.conf       # 複数台構成のロードバランシング設定
  nginx-upstream-keepalive.conf # nginx -> app 接続再利用設定
  nginx-final-no-access-log.conf # 最終ベンチ向け access_log off 設定
  mysql-remote.cnf          # MySQL 外部接続許可設定（DB サーバー分離時）
  mysql-buffer-pool.cnf     # innodb_buffer_pool_size 段階評価用
  mysql-durability-relaxed.cnf # fsync 緩和設定（競技向け）
  mysql-connection-cache.cnf # 接続・一時テーブル系設定
  memcached-competition.command # memcached 競技向け command 例
  redis-cache.conf          # Redis キャッシュ用途向け設定
  rds-parameter-group.md    # RDS パラメータグループ手動設定手順
  go-pprof.snippet          # Go pprof エンドポイント追加コード
  h2o-ltsv.conf             # H2O web server LTSV ログ設定
.claude/commands/
  isucon-survey.md          # /isucon-survey スキル（競技開幕の環境調査）
  isucon-analyze.md         # /isucon-analyze スキル
  isucon-multiserver.md     # /isucon-multiserver スキル（複数台構成）
  isucon-pprof.md           # /isucon-pprof スキル（Go pprof）
reports/                    # analyze.sh が生成するレポートの出力先
```

---

## 競技当日の使い方

### Phase 0 — 事前準備

```bash
git clone <this-repo> ~/isucon-tools
cd ~/isucon-tools
bash scripts/install-claude.sh
```

Claude Code がまだ入っていない端末では、リポジトリを clone した直後にこれを実行しておく。

### Phase 1 — 競技開始直後（最初の 5 分）

```
/isucon-survey
```

出力例:

```
## ISUCON 環境サマリー

### サーバー
- OS: Ubuntu 22.04 (x86_64)
- 実行環境: systemd
- Web サーバー: nginx 1.24
- アプリ: Go (サービス名: isu-go, ポート: 8080)
- webapp パス: /home/isucon/webapp

### DB
- 種別: ローカル MySQL
- ホスト: localhost
- ユーザー: isucon

### セットアップ手順

source scripts/env.sh
bash scripts/setup-tools.sh
bash scripts/setup-nginx.sh
bash scripts/setup-mysql.sh
bash scripts/setup-app.sh
```

出力されたセットアップ手順をそのまま実行する。

---

### Phase 2 — 改善ループ

このフェーズでは、複数エージェントで改善候補を並列実装し、改善したものだけを統合する。Claude Code には次の手順をそのまま投げる。

```text
/goal
競技中の改善ループを以下の手順で実行せよ。

前提:
- 統合先ブランチは `$APP_REPO` の `feature/isucon-work` とする。
- rebuild/restart と benchmark は必ず `$TOOL_REPO/scripts/bench-locked.sh` で実行し、他エージェントの rebuild/restart/benchmark と同時に実行しない。

ループ:
1. `APP_REPO="$(dirname "$ISUCON_WEBAPP_DIR")"` を設定し、`$APP_REPO` の `feature/isucon-work` に移動する。
2. `$TOOL_REPO/scripts/bench-locked.sh` を1回実行し、現在の基準スコアを確認する。
3. `$TOOL_REPO/scripts/analyze.sh` を実行し、その結果を `/isucon-analyze` スキルで分析する。
4. `/isucon-analyze` の結果から、高インパクト・中インパクトの提案だけを抽出する。
   - 抽出した候補は、候補ごとに `$TOOL_REPO/scripts/improvement-log.sh candidate ...` で記録する。
   - 候補ID、インパクト、難易度、予定ブランチ、改善方法を必ず残す。
5. 抽出した提案が存在しない、つまり小インパクトのみになったら終了する。
6. 高・中インパクトの提案を、提案項目1つにつき1つの独立 worktree/branch に分けて並列修正する。
   - ファイルやインパクトでまとめず、必ず提案単位で分ける。
   - 各作業ブランチは `feature/<短い内容>` のように命名する。
   - メインエージェントは候補抽出、worktree/branch作成、評価、merge採否だけを担当する。
   - 実装は候補ごとに別サブエージェントへ委譲する。同時実装数は最大5件までに制限する。
   - 各サブエージェントは割り当てられた1候補・1worktreeのみを編集する。
   - 各サブエージェントはコード修正、ローカルテスト、commit作成まで行い、結果をメインエージェントへ報告する。
   - 各サブエージェントは rebuild/restart、benchmark、merge を実行しない。
   - rebuild/restart、benchmark、merge はメインエージェントだけが直列に実行する。
7. 各修正ブランチごとに、`$TOOL_REPO/scripts/bench-locked.sh --rebuild` を実行する。
   - pass し、基準スコアより明確に改善した修正だけを merge 対象にする。
   - 採否は `$TOOL_REPO/scripts/improvement-log.sh eval ...` で記録する。
8. merge は `$APP_REPO` の `feature/isucon-work` に対して行い、commit を必ず残す。squash しない。
   - コンフリクトが出た場合は自動解決を試みる。
   - 解決後は、`$TOOL_REPO/scripts/bench-locked.sh --rebuild` を実行する。
   - pass し、スコア改善が維持される場合のみ merge を確定する。
   - 自動解決が不確実、またはスコア改善が消えた場合は、その修正は merge しない。
9. merge 後、改善スコアを `$TOOL_REPO/scripts/score-log.sh` で記録する。
10. 手順4で抽出した全ての高・中インパクト提案を評価し終えたら、手順2に戻る。
   - 未mergeのworktree/branchは勝手に削除しない。
   - 残す、後で消す、再評価する、の判断を `$TOOL_REPO/scripts/improvement-log.sh cleanup ...` で記録する。
11. `/isucon-analyze` の結果が小インパクトのみになるまで、このループを継続する。

禁止:
- `git reset --hard` などの破壊的操作
- unrelated changes の巻き戻し
- 複数提案を1つの worktree にまとめること
```

---

### Phase 2.5 — pprof サイクル

改善ループのスコアが伸び悩んだとき、alp・スロークエリでは見えないアプリ内部のCPUホットスポットを特定して修正する。Claude Code には次の手順をそのまま投げる。

```text
/goal
pprof によるCPUホットスポット分析と修正を以下の手順で実行せよ。

前提:
- `scripts/env.sh` を Read して ISUCON_RUNTIME・ISUCON_WEBAPP_DIR・DOCKER_COMPOSE_DIR・REBUILD_CMD・BENCH_CMD を確認する。
- 統合先ブランチは `$APP_REPO` の `feature/isucon-work` とする。
- rebuild/restart と benchmark は必ず `$TOOL_REPO/scripts/bench-locked.sh` で実行し、他エージェントの rebuild/restart/benchmark と同時に実行しない。

0. pprof が未導入なら導入する。
   - Go アプリの main ファイルを探す: `find "$ISUCON_WEBAPP_DIR" -name "main.go" -o -name "app.go" | head -5`
   - `import _ "net/http/pprof"` と `go func() { http.ListenAndServe("0.0.0.0:6060", nil) }()` が存在するか確認する。
   - 存在しない場合: `templates/go-pprof.snippet` を参考に追加する。
   - Docker Compose 環境の場合: `$DOCKER_COMPOSE_DIR/docker-compose.pprof.yml` に 127.0.0.1:6060:6060 のポート公開が存在するか確認する。存在しない場合は追加する。
   - 変更があった場合: `$TOOL_REPO/scripts/bench-locked.sh --rebuild` で再ビルドする。
   - 変更がなかった場合: リビルド不要。

1. ベンチマークをバックグラウンドで起動し、同時にCPUプロファイルを取得する。

   PPROF_OUT="$TOOL_REPO/reports/pprof-$(date +%Y%m%d-%H%M%S)"
   eval "$BENCH_CMD" > "${PPROF_OUT}-bench.txt" 2>&1 &
   BENCH_PID=$!
   sleep 5  # アプリが負荷を受け始めるまで待機
   curl -s "http://localhost:6060/debug/pprof/profile?seconds=25" -o "${PPROF_OUT}.pprof"
   wait $BENCH_PID

   - ベンチマーク結果（${PPROF_OUT}-bench.txt）からスコアを確認して記録する。

2. プロファイルをテキストに変換してファイルに保存する。

   go tool pprof -top "${PPROF_OUT}.pprof" > "${PPROF_OUT}-top.txt"
   echo "--- cum ---" >> "${PPROF_OUT}-top.txt"
   go tool pprof -top -cum "${PPROF_OUT}.pprof" >> "${PPROF_OUT}-top.txt"

3. `/isucon-analyze ${PPROF_OUT}-top.txt` を呼び出して分析する。
   - alp・スロークエリに加えて pprof の top/cum 結果も合わせて解釈する。

4. 高・中インパクトの提案を抽出する。
   - 提案がない（小インパクトのみ）なら終了する。

5. 提案を1つにつき1つの独立 worktree/branch で並列修正する。
   - Phase 2 の改善ループと同じルールに従う（最大5件並列、サブエージェントへ委譲）。
   - 各修正を `$TOOL_REPO/scripts/bench-locked.sh --rebuild` で評価し、改善が確認できたものだけ `feature/isucon-work` に merge する。
   - merge 後は `$TOOL_REPO/scripts/score-log.sh` でスコアを記録する。
   - 全提案を評価したら手順1に戻る。

禁止:
- ベンチマーク実行中のリビルド・再起動
- 複数提案を1つの worktree にまとめること
- `git reset --hard` などの破壊的操作
```

---

### Phase 2.6 — ミドルウェア秘伝のタレ評価

アプリ改善と pprof 分析が一巡したら、MySQL / nginx / memcached / Redis の定番設定を単体差分で評価する。テンプレートは `templates/` に分割してあるので、効いたものだけ残す。

```text
/goal
ミドルウェアの秘伝のタレ系チューニングを、単体差分で段階評価してください。

前提:
- ツールリポジトリで `source scripts/env.sh` して、`TOOL_REPO`・`ISUCON_RUNTIME`・`DOCKER_COMPOSE_DIR`・`DOCKER_COMPOSE_FILE_ARGS`・`DOCKER_MYSQL_SERVICE`・`NGINX_CONF_HOST_DIR`・`BENCH_CMD`・`REBUILD_CMD` を確認する。
- ベンチは必ず `$TOOL_REPO/scripts/bench-locked.sh --rebuild` で実行する。
- 変更は1テーマずつ行い、複数設定をまとめて入れない。
- 悪化、fail、効果不明なら戻す。
- 採用/却下理由とスコアを `$TOOL_REPO/reports/infra-tuning.md` に記録する。
- 分析用ログと最終スコア用ログ抑制は分けて扱う。

0. 現状ベースラインを測定する。
   - `$TOOL_REPO/scripts/bench-locked.sh --rebuild`
   - `$TOOL_REPO/scripts/analyze.sh`
   - スコアを `$TOOL_REPO/scripts/score-log.sh <score> "infra baseline"` で記録する。
   - MySQL の現状値を確認する: `docker compose $DOCKER_COMPOSE_FILE_ARGS exec -T "$DOCKER_MYSQL_SERVICE" mysql -u"$DB_ADMIN_USER" -p"$DB_ADMIN_PASS" -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size'; SHOW VARIABLES LIKE 'innodb_flush_log_at_trx_commit'; SHOW VARIABLES LIKE 'sync_binlog';"`

1. MySQL buffer pool を段階評価する。
   - Docker 環境では `$DOCKER_COMPOSE_DIR/etc/mysql/20-buffer-pool.cnf` に `$TOOL_REPO/templates/mysql-buffer-pool.cnf` を `<BUFFER_POOL_SIZE>` 置換して配置する。
     ```bash
     mkdir -p "$DOCKER_COMPOSE_DIR/etc/mysql"
     sed "s/<BUFFER_POOL_SIZE>/256M/g" \
       "$TOOL_REPO/templates/mysql-buffer-pool.cnf" \
       > "$DOCKER_COMPOSE_DIR/etc/mysql/20-buffer-pool.cnf"
     ```
   - systemd + local MySQL では `/etc/mysql/conf.d/20-buffer-pool.cnf` または `/etc/my.cnf.d/20-buffer-pool.cnf` に配置する。
   - `256M` を適用してベンチ、次に `512M`、余裕があれば `768M` を単体評価する。
   - 最もスコアが良い値だけ残し、他は戻す。

2. MySQL durability relaxed 設定を単体評価する。
   - `$TOOL_REPO/templates/mysql-durability-relaxed.cnf` を `21-durability-relaxed.cnf` として配置する。
     ```bash
     cp "$TOOL_REPO/templates/mysql-durability-relaxed.cnf" \
       "$DOCKER_COMPOSE_DIR/etc/mysql/21-durability-relaxed.cnf"
     ```
   - `innodb_flush_log_at_trx_commit=2` と `sync_binlog=0` はクラッシュ耐久性を緩めるため、競技中のベンチ用途として採否を明記する。
   - 改善しなければ削除して戻す。

3. MySQL connection/cache 系を単体評価する。
   - `$TOOL_REPO/templates/mysql-connection-cache.cnf` を `22-connection-cache.cnf` として配置する。
     ```bash
     cp "$TOOL_REPO/templates/mysql-connection-cache.cnf" \
       "$DOCKER_COMPOSE_DIR/etc/mysql/22-connection-cache.cnf"
     ```
   - 改善しなければ削除して戻す。

4. nginx upstream keepalive を単体評価する。
   - `$TOOL_REPO/templates/nginx-upstream-keepalive.conf` を参考に、既存 nginx 設定へ upstream と proxy_http_version / Connection ヘッダだけを差分適用する。
   - Docker 環境では `$NGINX_CONF_HOST_DIR` 配下の既存 server 設定を編集する。
   - systemd 環境では `sudo nginx -t`、Docker 環境では `docker compose $DOCKER_COMPOSE_FILE_ARGS exec -T "$DOCKER_NGINX_SERVICE" nginx -t` で設定テストしてからベンチする。
   - 改善しなければ差分を戻す。

5. memcached 設定を必要な場合だけ評価する。
   - memcached がセッションまたはキャッシュ用途で使われている場合、`$TOOL_REPO/templates/memcached-competition.command` を参考に `-m 256 -c 4096 -t 2` を単体評価する。
   - 正データを保持している場合は実施しない。

6. Redis 設定を Redis 採用環境で必要な場合だけ評価する。
   - Redis がキャッシュ用途なら `$TOOL_REPO/templates/redis-cache.conf` を参考に persistence off と maxmemory-policy を評価する。
   - Redis が正データの場合、`save ""` と `appendonly no` は使わない。

7. 最終スコア用ログ抑制を評価する。
   - 分析が完了してから、MySQL slow query log off と nginx access_log off を別々に評価する。
   - nginx は `$TOOL_REPO/templates/nginx-final-no-access-log.conf` を参考にする。
   - ログ抑制中は alp / pt-query-digest が使えないので、分析用設定とは別の最終測定として記録する。

8. `$TOOL_REPO/reports/infra-tuning.md` にまとめる。
   - baseline score
   - 各候補の設定差分
   - score
   - pass/fail
   - 採用/却下
   - 最終採用設定

禁止:
- `git reset --hard` などの破壊的操作
- unrelated changes の巻き戻し
- 複数テーマをまとめて評価すること
- 分析用ログ設定と最終ログ抑制設定を同じ測定として扱うこと
```

---

## スクリプトリファレンス

### `scripts/analyze.sh`

ベンチ結果を解析して、アクセスログとスロークエリログの集計レポートを生成する shell。`scripts/env.sh` を読んで、環境に合わせた入力と出力先を決める。

```bash
bash scripts/analyze.sh
```

### `scripts/bench-locked.sh`

再起動と benchmark を同じ排他ロックに入れて実行する shell。再起動直後の待機確認も含め、評価中の同時実行を避ける。

```bash
bash scripts/bench-locked.sh

bash scripts/bench-locked.sh --rebuild

bash scripts/bench-locked.sh --no-reset-logs

HEALTHCHECK_CMD='curl -fsS http://localhost/initialize >/dev/null' \
bash scripts/bench-locked.sh --rebuild
```

### `scripts/score-log.sh`

ベンチ結果のスコアを履歴として追記する shell。対象 commit とメモも残すので、どの修正で改善したかを追える。

```bash
bash scripts/score-log.sh <score> [メモ]

# 例
bash scripts/score-log.sh 3200 "N+1解消"
bash scripts/score-log.sh 5800 "画像をファイルシステムに移動"
```

---

## Claude Code スキルリファレンス

### `/isucon-survey`

競技開始直後にサーバーを調査し、環境サマリーと推奨セットアップコマンドを提示する。  
OS / アーキテクチャ・動作サービス・アプリのサービスファイル・DB 接続情報（`EnvironmentFile=` 参照先も読む）・DB 種別（ローカル / RDS / Aurora）・静的ファイルパスを一括調査する。

```
/isucon-survey
```

出力例:
```
## ISUCON 環境サマリー

### サーバー
- OS: Ubuntu 22.04 (x86_64)
- Web サーバー: nginx 1.24
- アプリ: Go (サービス名: isu-go, ポート: 8080)
- webapp パス: /home/isucon/webapp

### DB
- 種別: ローカル MySQL
- ホスト: localhost
- ユーザー: isucon

### 推奨セットアップコマンド
bash scripts/setup-tools.sh
bash scripts/setup-nginx.sh
bash scripts/setup-mysql.sh
bash scripts/setup-app.sh
```

### `/isucon-analyze`

`reports/` の最新レポートを読んで改善優先順位 TOP5 を提示する。  
`analyze.sh` 実行後に使う。

---

## テンプレートリファレンス

### `templates/nginx-ltsv.conf`

nginx の access log を LTSV 形式で出力するための設定。手動で適用する場合:

```bash
sudo cp templates/nginx-ltsv.conf /etc/nginx/conf.d/ltsv.conf
sudo nginx -t && sudo systemctl reload nginx
```

### `templates/mysql-slow.cnf`

MySQL の slow query log を有効化・調整するための設定。手動で適用する場合:

```bash
# Ubuntu / Debian
sudo cp templates/mysql-slow.cnf /etc/mysql/conf.d/slow-query.cnf
sudo systemctl restart mysql

# Amazon Linux 2 / 2023
sudo cp templates/mysql-slow.cnf /etc/my.cnf.d/slow-query.cnf
sudo systemctl restart mysqld
```

### `templates/nginx-staticfile.conf`

静的ファイルを nginx から直接配信するための設定。DB から画像をファイルシステムへ移した後に使う。
