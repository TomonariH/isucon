# /isucon-multiserver

複数台構成（2〜3台）の ISUCON 環境で、最新レポートと現在の実行環境から最適な役割分担を設計し、必要ならこのサーバー内で実施可能な修正を新規ブランチで適用する。

このスキルは長い反復ループではなく、**調査 → 分割案 → 手順提示 → 実施可能なローカル修正 → 検証計画** までを1回で出す。複数案を実際にベンチで反復評価する場合は、別途 `/goal` でこのスキルの出力を正本にして実行する。

## Steps

0. **`scripts/env.sh` と最新レポートを Read して前提を把握する**

   確認する変数: `TOOL_REPO`・`ISUCON_RUNTIME`・`ISUCON_WEBAPP_DIR`・`NGINX_ACCESS_LOG`・`MYSQL_SLOW_LOG`・`DB_HOST`・`DB_USER`・`DB_PASS`・`DB_NAME`・`BENCH_CMD`・`REBUILD_CMD`

   追加で確認する:
   - `reports/` の最新レポート（alp / slow query）
   - `reports/scores.md`
   - `reports/survey.md`
   - 既存の `reports/multiserver.md` があればその採否と未解決課題

   最新レポートから次を読み取る:
   - nginx/app/DB のどこが詰まっているか
   - app を増やすべきか、DBを分離すべきか、nginx/static配信だけを分けるべきか
   - DB が主ボトルネックの場合、app 増設が逆効果にならないか
   - 画像/静的ファイル/セッション共有が必要か

1. **現在のレギュレーション・実行環境を確認する**

   ISUCONのレギュレーションは年度・回によって変わるので推測しない。以下のいずれかで確認する:
   - 競技ページ、README、当日資料、運営ドキュメントがローカルにあれば読む
   - URL が分かる場合は公式情報を確認する
   - 不明な場合はユーザーに確認する

   確認する観点:
   - 使用可能なサーバー台数
   - ベンチマーカーが叩く入口IP/URL
   - サーバー間通信・データコピー・DB移動・プロセス追加の可否
   - Docker Compose / systemd / cloud LB / RDS などの制約
   - 再起動・初期化・最終ベンチ時の起動方法

2. **現在のサーバー構成を確認する**

   自動調査できるものは調査し、不明な点だけユーザーに確認する:
   - 台数（2台 or 3台）
   - 各サーバーのIP / hostname / SSH可否
   - 各サーバーのスペック（CPU コア数・メモリ）
   - 現在のサービス配置（どのサーバーで nginx / app / MySQL が動いているか）
   - Redis / memcached / object storage / 画像保存先
   - app の listen port と DB/cache 接続先

   このサーバー内で使える調査例:
   ```bash
   hostname -I
   nproc
   free -h
   systemctl list-units --type=service --state=active --no-pager
   docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' 2>/dev/null || true
   ss -ltnp
   ```

   リモートサーバーへSSHできる場合も、勝手に破壊的変更はせず、まず調査だけ行う。

3. **最新レポートに基づいて最適な役割分担を提案する**

   役割分担は固定パターンで決めず、最新レポートと資源使用率で決める:
   - app CPU が高く DB に余裕がある → app 増設/分離を優先
   - DB CPU/I/O/slow query が高い → DB分離、MySQL設定、クエリ削減を優先。app増設は慎重にする
   - nginx/static配信が重い → nginx/static専用化、キャッシュ、直配信を優先
   - セッション/画像がローカル依存 → app複数台化前に共有化が必要

   **2台構成（典型的なパターン）**:
   ```
   server1 (nginx 専用 + ロードバランサー):
     - nginx でリクエストを受けて app サーバーに振る
     - 静的ファイルもここで直接配信
   
   server2 (app + MySQL):
     - アプリ + DB を同居
     - app が多い場合は DB を server1 に移す
   ```

   **3台構成（推奨）**:
   ```
   server1: nginx + 静的ファイル配信
   server2: app (Go/Ruby/Python など)
   server3: MySQL / Redis
   ```

   Docker Compose 環境での簡易スケール案:
   - app service が host port を公開している場合、`--scale app=2` はポート衝突するため不可
   - pprof など固定 host port の override がある場合、app複数台化前に外す
   - nginx upstream は service名（例: `app:8080`）または固定IP/別service名に向ける

4. **手順提示に必要な不明点を解消する**

   手順の安全性に関わる情報が不足している場合は、推測で進めない。次を優先して確認する:
   - benchmark入口URL
   - app/DB/cache の接続先変更方法
   - SSH可能なサーバーとsudo権限
   - DBデータ移行/初期化方法
   - 画像・アップロードファイル・セッションの共有方式

   確認できない場合は、実施手順を「未確定」として明示し、ユーザーへの質問を出す。

5. **nginx upstream 設定を生成する**

   `templates/nginx-upstream.conf` をベースに、実際の IP アドレスに書き換えた設定を出力する:

   ```nginx
   upstream app {
     least_conn;
     server <app-server-1-ip>:8080;
     server <app-server-2-ip>:8080;  # 3台構成の場合
     keepalive 32;
   }
   ```

   注意:
   - 既存の `server_name` / TLS / root / 静的ファイル location / access_log を消さない
   - `proxy_http_version 1.1` と `proxy_set_header Connection ""` を入れる
   - nginx設定変更後は必ず `nginx -t` を実行する

6. **MySQL 外部接続設定を案内する**

   DB サーバーを分離する場合、DB サーバー側で MySQL サービス名と設定ディレクトリを確認してから実行する:
   ```bash
   # サービス名を確認（mysql / mysqld / mariadb のいずれか）
   systemctl list-units --type=service | grep -E 'mysql|mariadb'

   # 設定ディレクトリを確認（Debian 系: /etc/mysql/conf.d  RHEL 系: /etc/my.cnf.d）
   ls /etc/mysql/conf.d 2>/dev/null || ls /etc/my.cnf.d 2>/dev/null

   # 確認した設定ディレクトリにコピーしてサービスを再起動
   sudo cp templates/mysql-remote.cnf <確認した設定ディレクトリ>/remote.cnf
   sudo systemctl restart <確認したサービス名>

   # アプリサーバーからの接続を許可するユーザー作成
   # DB名・ユーザー名・パスワード・接続元IPは実環境の値に置き換える
   mysql -e "CREATE USER IF NOT EXISTS 'isucon'@'<app-server-ip>' IDENTIFIED BY '<password>';"
   mysql -e "GRANT ALL PRIVILEGES ON isucon.* TO 'isucon'@'<app-server-ip>';"
   mysql -e "FLUSH PRIVILEGES;"
   ```

7. **各サーバーでのセットアップを案内する**

   役割に応じて必要なスクリプトだけ実行する:
   ```bash
   # nginx サーバー (server1) で実行
   bash scripts/setup-tools.sh
   bash scripts/setup-nginx.sh
   # webapp がこのサーバーにも配置されている場合のみ:
   # bash scripts/setup-app.sh
   sudo nginx -T | grep -E 'server_name|proxy_pass|include .*(conf.d|sites-enabled)'
   # templates/nginx-upstream.conf を参考に、既存の server block へ upstream と proxy_pass の差分だけを反映する
   sudoedit <既存の nginx server 設定ファイル>
   sudo nginx -t && sudo systemctl reload nginx

   # app サーバー (server2, 3) で実行
   bash scripts/setup-tools.sh
   bash scripts/setup-app.sh

   # DB サーバー (server3) で実行
   bash scripts/setup-mysql.sh  # MySQL のサービス名・conf dir を自動検出
   ```

8. **このサーバー内で agent が実施可能な修正を行う**

   スキルが実行されているサーバー内で完結し、かつ安全に検証できる変更がある場合だけ実施する。

   実施ルール:
   - 変更前に app repo を確認し、新規ブランチを作る
     ```bash
     APP_REPO="$(dirname "$ISUCON_WEBAPP_DIR")"
     git -C "$APP_REPO" switch -c feature/multiserver-<short-name>
     ```
   - nginx設定、Docker Compose override、app env、MySQL grant など、このサーバー内で変更できるものだけ編集する
   - 変更後は `nginx -t`、DB疎通、app healthcheck など、ベンチ前の軽い確認を行う
   - benchmark はユーザーが明示した場合、またはこのスキルの実行目的が適用検証である場合だけ実行する
   - fail が出た場合は即戻さず、benchmark messages、app/nginx/MySQLログ、access log、slow query から原因を特定して修正を試みる
   - 実施した変更は commit する。未確定・危険・リモート手作業が必要な変更は commit せず、手順として提示する

   汎用的に実施しやすいローカル変更例:
   - nginx upstream / keepalive / proxy header の差分適用
   - Docker Compose の app scale 用 override 作成（host port衝突がない場合）
   - DB_HOST / cache host の env 変更案作成
   - MySQL の appサーバーIP向けユーザー作成（DBがこのサーバー内で操作可能な場合）
   - scripts/env.sh のログパスや compose args の更新

9. **分散環境での分析手順を案内する**

   各サーバーで個別に analyze.sh を実行してレポートを収集する:

   ```bash
   # nginx サーバーでアクセスログ分析
   bash scripts/analyze.sh
   
   # DB サーバーでスロークエリ分析（MySQL が DB サーバーにある場合）
   # MYSQL_SLOW_LOG は env.sh の値を使う（systemd なら /var/log/mysql/slow.log が多い）
   MYSQL_SLOW_LOG="$MYSQL_SLOW_LOG" bash scripts/analyze.sh
   ```

   レポートを一か所に集める場合:
   ```bash
   # nginx サーバーで実行（DB サーバーからレポートを取得）
   scp isucon@server3:~/isucon-tools/reports/*.md reports/
   ```

10. **検証・採否・ロールバック手順を提示する**

   最低限含める:
   - 変更前ベースラインの取り方
   - 分割後の疎通確認
   - ベンチ実行コマンド
   - nginx/app/DB/cache別のログ確認コマンド
   - 採用条件: pass、明確なスコア改善、p99/エラー率悪化なし
   - 却下条件: DB RTT悪化、画像/静的ファイル不整合、セッション不整合、MySQL接続詰まり、fail原因が解消できない
   - ロールバック手順

11. **ボトルネック特定の視点を追加する**

   複数台ならではのボトルネック:
   - サーバー間通信のレイテンシ（DB サーバーへの RTT が積み上がる）
   - nginx → app の proxy が遅い場合は `keepalive` の設定を確認
   - app を 2 台に増やしても DB がボトルネックなら意味がない
   - `SHOW PROCESSLIST` でスレッドが詰まっていないか確認

## Output Format

```markdown
## マルチサーバー構成プラン

**台数**: N 台

### 役割分担
| サーバー | IP | 役割 |
|---------|-----|------|
| server1 | 192.168.0.2 | nginx |
| server2 | 192.168.0.3 | app |
| server3 | 192.168.0.4 | MySQL |

### nginx upstream 設定
[生成した設定]

### セットアップ手順
[各サーバー別の手順]

### このサーバーで実施した変更
[ブランチ名、変更ファイル、commit、検証結果。未実施なら理由]

### 検証・採否・ロールバック
[ベースライン、ベンチ手順、採用条件、戻し方]

### 注意点
[この構成特有のボトルネック]
```
