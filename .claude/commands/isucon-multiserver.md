# /isucon-multiserver

複数台構成（2〜3台）の ISUCON 環境でサーバー役割を設計し、セットアップ手順を案内する。

## Steps

1. **現在のサーバー構成を確認する**  
   ユーザーに以下を確認する:
   - 台数（2台 or 3台）
   - 各サーバーのスペック（CPU コア数・メモリ）
   - 現在のサービス配置（どのサーバーで nginx / app / MySQL が動いているか）

2. **最適な役割分担を提案する**

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

3. **nginx upstream 設定を生成する**

   `templates/nginx-upstream.conf` をベースに、実際の IP アドレスに書き換えた設定を出力する:

   ```nginx
   upstream app {
     least_conn;
     server <app-server-1-ip>:8080;
     server <app-server-2-ip>:8080;  # 3台構成の場合
     keepalive 32;
   }
   ```

4. **MySQL 外部接続設定を案内する**

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

5. **各サーバーでのセットアップを案内する**

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

6. **分散環境での分析手順を案内する**

   各サーバーで個別に analyze.sh を実行してレポートを収集する:

   ```bash
   # nginx サーバーでアクセスログ分析
   bash scripts/analyze.sh
   
   # DB サーバーでスロークエリ分析（MySQL が DB サーバーにある場合）
   MYSQL_SLOW_LOG=/var/log/mysql/slow.log bash scripts/analyze.sh
   ```

   レポートを一か所に集める場合:
   ```bash
   # nginx サーバーで実行（DB サーバーからレポートを取得）
   scp isucon@server3:~/isucon-tools/reports/*.md reports/
   ```

7. **ボトルネック特定の視点を追加する**

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

### 注意点
[この構成特有のボトルネック]
```
