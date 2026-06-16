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
  nginx-00-ltsv.conf        # nginx LTSV アクセスログ設定
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
   - fail が出た場合、即ロールバック・即却下しない。まず `bench-locked.sh` の出力 `messages`、benchmark stdout/stderr、app/nginx/MySQL のログ、`$TOOL_REPO/scripts/analyze.sh` の access log / slow query を確認し、ログに基づいて正確な原因を特定する。
   - fail 原因を推測で決めない。静的ファイル不整合、セッション不整合、DB接続エラー、initialize漏れ、nginx直配信パス不整合など、観測したログ・エラーメッセージ・再現コマンドを `$TOOL_REPO/scripts/improvement-log.sh eval ...` の note に残す。
   - 原因がその修正内で解消できる場合は、同じ worktree/branch で追加修正して再度 `$TOOL_REPO/scripts/bench-locked.sh --rebuild` を実行する。
   - ログから原因を特定できない、または修正しても fail が解消しない場合のみ、その候補を merge 対象から外す。
   - 採否は `$TOOL_REPO/scripts/improvement-log.sh eval ...` で記録する。
8. merge は `$APP_REPO` の `feature/isucon-work` に対して行い、commit を必ず残す。squash しない。
   - コンフリクトが出た場合は自動解決を試みる。
   - 解決後は、`$TOOL_REPO/scripts/bench-locked.sh --rebuild` を実行する。
   - fail が出た場合は手順7と同じく、必ずログから正確な原因を特定して解消を試みる。推測でロールバックしない。
   - pass し、スコア改善が維持される場合のみ merge を確定する。
   - 自動解決が不確実、ログに基づく原因解消ができない、またはスコア改善が消えた場合は、その修正は merge しない。
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

### Phase 3 — pprof サイクル

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

### Phase 4 — ミドルウェア秘伝のタレ評価

アプリ改善と pprof 分析が一巡したら、MySQL / nginx / memcached / Redis の定番設定を単体差分で評価する。テンプレートは `templates/` に分割してあるので、効いたものだけ残す。

```text
/goal
ミドルウェアの秘伝のタレ系チューニングを、単体差分で段階評価してください。

前提:
- ツールリポジトリで `source scripts/env.sh` して、`TOOL_REPO`・`ISUCON_RUNTIME`・`DOCKER_COMPOSE_DIR`・`DOCKER_COMPOSE_FILE_ARGS`・`DOCKER_MYSQL_SERVICE`・`NGINX_CONF_HOST_DIR`・`BENCH_CMD`・`REBUILD_CMD` を確認する。
- ベンチは必ず `$TOOL_REPO/scripts/bench-locked.sh --rebuild` で実行する。
- 変更は1テーマずつ行い、複数設定をまとめて入れない。
- 悪化、効果不明なら戻す。fail が出た場合は即戻さず、必ず benchmark messages、app/nginx/MySQL ログ、access log、slow query から正確な原因を特定し、解消を試みてから採否を決める。
- 採用/却下理由とスコアを `$TOOL_REPO/reports/infra-tuning.md` に記録する。
- Phase 4 では分析用ログを維持する。MySQL slow query log off、nginx access_log off、pprof削除、分析用 override の整理などの最終提出作業は Phase 6 でのみ行う。

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

7. Phase 6 に送る最終整備候補を記録する。
   - MySQL slow query log off、nginx access_log off、pprof削除、分析用 override の整理などは、このPhaseでは実施しない。
   - 最終スコア用に試す価値がある候補として `$TOOL_REPO/reports/infra-tuning.md` に記録し、実作業は Phase 6 に回す。
   - Phase 4中にログを止めると fail 原因や性能劣化の分析ができなくなるため禁止する。

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
- MySQL slow query log off、nginx access_log off、pprof削除、分析用 override 整理など Phase 6 の最終提出作業を実施すること
- 分析用ログ設定と最終ログ抑制設定を同じ測定として扱うこと
```

---

### Phase 5 — サーバー分割

1台構成でアプリ改善・pprof・ミドルウェア調整が一巡し、CPU / メモリ / DB のどれかが明確に上限に近い場合だけ、複数台構成を検討する。サーバー間通信が増えるので、DB が細かいクエリを大量に受けている状態では、分割前に N+1 とインデックスを優先する。

```text
/goal
サーバー分割を、計測とロールバック可能性を保ったまま設計・適用してください。

前提:
- ツールリポジトリで `source scripts/env.sh` して、`TOOL_REPO`・`ISUCON_WEBAPP_DIR`・`DB_HOST`・`DB_USER`・`DB_PASS`・`DB_NAME`・`BENCH_CMD`・`REBUILD_CMD` を確認する。
- まず `/isucon-multiserver` の手順に従い、台数・IP・各サーバーのCPU/メモリ・現在の nginx / app / MySQL / Redis / memcached 配置を確認する。
- benchmark は必ず1つだけ実行する。他goal・他エージェントの rebuild / restart / benchmark と同時に実行しない。
- 変更前後でスコア、pass/fail、各サーバーのCPU/メモリ、alp、slow query を記録する。
- 分割して悪化したら元の1台構成に戻す。

0. 分割前の基準を固定する。
   - `$TOOL_REPO/scripts/bench-locked.sh --rebuild`
   - `$TOOL_REPO/scripts/analyze.sh`
   - `$TOOL_REPO/scripts/score-log.sh <score> "multiserver baseline"`
   - `top` / `vmstat` / `docker stats` / `SHOW PROCESSLIST` などで、詰まっている資源を記録する。

1. 役割分担を決める。
   - 2台構成の第一候補:
     - server1: nginx + 静的ファイル配信
     - server2: app + MySQL
   - 3台構成の第一候補:
     - server1: nginx + 静的ファイル配信
     - server2: app
     - server3: MySQL
   - app を複数台に増やすのは、DB が詰まっていないことを確認してからにする。

2. nginx サーバーを設定する。
   - `$TOOL_REPO/templates/nginx-upstream.conf` を参考に、既存 server block へ upstream と proxy_pass の差分だけを反映する。
   - `server_name` / TLS / root / 静的ファイル location / access_log を消さない。
   - `proxy_http_version 1.1` と `proxy_set_header Connection ""` を入れ、upstream keepalive を有効にする。
   - `sudo nginx -t && sudo systemctl reload nginx` で確認する。

3. DB サーバーを分離する場合は MySQL 外部接続を設定する。
   - DB サーバーで `$TOOL_REPO/templates/mysql-remote.cnf` を参考に `bind-address=0.0.0.0` を設定する。
   - app サーバーのIPだけを許可する MySQL ユーザーを作る。
   - app 側の `DB_HOST` / `ISUCONP_DB_HOST` を DB サーバーのプライベートIPへ変更する。
   - app サーバーから `mysql -h <db-server-ip> -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT 1"` で疎通確認する。

4. app サーバーを分離または増設する。
   - app サーバーごとに同じ revision の webapp を配置する。
   - 環境変数、静的ファイル、画像保存先、memcached / Redis 接続先が全appで一致しているか確認する。
   - セッション保存先がローカルメモリの場合、複数app化で壊れるため、共有 memcached / Redis に寄せる。

5. 分割後にベンチする。
   - nginx サーバーから benchmark 対象URLへ流す。
   - ベンチ中に各サーバーでCPU/メモリ/ネットワーク/DB接続数を観察する。
   - ベンチ後、nginx サーバーと DB サーバーのログをそれぞれ分析し、必要ならレポートを `$TOOL_REPO/reports/` に集約する。
   - `$TOOL_REPO/scripts/score-log.sh <score> "multiserver <構成メモ>"` で記録する。

6. 採否を決める。
   - pass し、基準スコアより明確に改善し、エラー率やp99が悪化していなければ採用する。
   - DB の RTT 増加、画像/静的ファイル不整合、セッション不整合、MySQL接続詰まりが出たら戻す。
   - 採用/却下理由、役割分担、IP、設定差分、スコアを `$TOOL_REPO/reports/multiserver.md` にまとめる。

禁止:
- DB_HOST 変更だけして疎通確認せずにベンチすること
- app revision がサーバー間でずれたまま評価すること
- ローカルファイル保存の画像やセッションを共有せずに app を複数台化すること
- 分割後の悪化を「揺らぎ」として採用すること
```

---

### Phase 6 — 最終提出用のサーバー整備

提出直前は、分析用の重いログ・pprof・一時ファイル・未採用設定を外し、再起動後も同じ構成で起動することを確認する。ここでは新しい最適化を増やさず、採用済み変更の固定と事故防止に集中する。

```text
/goal
最終提出用にサーバー状態を整備し、再起動後も採用構成でベンチが通ることを確認してください。

前提:
- ツールリポジトリで `source scripts/env.sh` して、`TOOL_REPO`・`ISUCON_RUNTIME`・`ISUCON_WEBAPP_DIR`・`BENCH_CMD`・`REBUILD_CMD` を確認する。
- これ以降は新規チューニングを追加しない。採用済み設定の固定、不要設定の無効化、再現性確認だけを行う。
- benchmark は必ず1つだけ実行する。他goal・他エージェントの rebuild / restart / benchmark と同時に実行しない。
- 最終整備前後のスコアを `$TOOL_REPO/scripts/score-log.sh` で記録する。

0. 採用済み変更を確認する。
   - app リポジトリの branch / commit / diff を確認する。
   - 採用した nginx / MySQL / Redis / memcached / systemd / Docker Compose 設定を一覧化する。
   - 未採用・評価途中の設定ファイルを残していないか確認する。

1. 分析用設定を外す。
   - pprof 用ポート公開、`net/http/pprof`、pprof goroutine は最終スコアに不要なら外す。
   - MySQL slow query log は最終測定用に off へ戻すか、少なくとも `long_query_time=0` をやめる。
   - nginx access log は最終測定用に off または軽量化する。ただし、提出前の最後の原因調査が必要なら一時的に戻せるよう差分を記録する。
   - Docker Compose 環境では、分析専用 override (`docker-compose.isucon-logs.yml`, `docker-compose.pprof.yml` など) に最終構成が依存していないか確認する。

2. 起動経路を固定する。
   - systemd 環境では `systemctl cat <service>` を確認し、再起動後に正しい binary / env / WorkingDirectory が使われることを確認する。
   - Docker Compose 環境では、最終ベンチで使う compose ファイル列を明確にする。
   - 最終スコアに必要な設定は通常起動で読まれる場所に置く。分析用 override だけに必要設定を置かない。
   - nginx / app / DB / cache を再起動しても採用設定が残ることを確認する。

3. データ初期化と静的ファイルを確認する。
   - `/initialize` 後に画像・アップロードファイル・生成済み静的ファイルが期待位置に存在するか確認する。
   - app 複数台構成の場合、画像保存先やセッション保存先が全appで共有されているか確認する。
   - nginx 直配信している path が、initialize 後も stale file を返さないことを確認する。

4. 最終ベンチ相当で測定する。
   - 採用済み構成だけで rebuild / restart する。
   - `$TOOL_REPO/scripts/bench-locked.sh --rebuild`
   - pass / score / messages を確認し、`$TOOL_REPO/scripts/score-log.sh <score> "final server prep"` で記録する。
   - fail、静的ファイル不整合、セッション不整合、DB接続エラーがあれば、最終整備の変更を戻して再測定する。

5. 再起動後の再現性を確認する。
   - 競技ルール上許される範囲で、サービス再起動または Docker Compose の `up -d` を実行する。
   - 起動後に nginx / app / DB / cache の状態を確認する。
   - もう一度ベンチを実行し、pass とスコア水準が維持されることを確認する。

6. 最終メモを残す。
   - `$TOOL_REPO/reports/final-prep.md` に以下をまとめる:
     - 最終 app commit
     - 最終 compose / systemd / nginx / MySQL / cache 設定
     - 外した分析用設定
     - 最終ベンチスコア
     - 再起動後ベンチスコア
     - 既知のリスク

禁止:
- 提出直前に未評価の最適化を追加すること
- pprof や slow query `long_query_time=0` を最終構成に残したまま、理由なく提出すること
- 分析用 override にしか存在しない設定へ最終構成を依存させること
- pass していない構成を最終構成として扱うこと
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

### `templates/nginx-00-ltsv.conf`

nginx の access log を LTSV 形式で出力するための設定。手動で適用する場合:

```bash
sudo cp templates/nginx-00-ltsv.conf /etc/nginx/conf.d/ltsv.conf
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
