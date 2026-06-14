# /isucon-survey

ISUCON 競技開始直後の環境調査を行い、セットアップに必要な情報をすべてまとめて提示する。

## Steps

1. **サーバー基本情報を取得する**

   以下のコマンドを実行する:
   ```bash
   uname -m
   grep -E '^(ID|ID_LIKE|VERSION_ID)=' /etc/os-release
   ```

2. **動いているサービスを確認する**

   以下のコマンドを実行し、Web サーバー・アプリ・DB を特定する:
   ```bash
   systemctl list-units --type=service --state=active --no-pager
   ```
   出力から以下を探す:
   - **Web サーバー**: nginx / h2o / apache2 / httpd
   - **アプリ**: isu* / app* / go* / ruby* / python* / node* / php* / perl* を含むもの
   - **DB（ローカル）**: mysql / mysqld / mariadb / postgresql / redis

3. **アプリのサービスファイルから webapp パスと環境変数を取得する**

   手順2で特定したアプリのサービス名を使って実行する:
   ```bash
   sudo systemctl cat <app-service-name>
   ```
   以下を読み取る:
   - `WorkingDirectory=` → webapp のパス
   - `Environment=` → DB 接続情報（HOST / PORT / USER / PASSWORD / NAME）
   - `EnvironmentFile=` → 参照先ファイルのパスを記録し、**必ずそのファイルを `cat` して** 接続情報を取得する
   - `ExecStart=` → 実行バイナリ・言語の確認

4. **アプリのソースコードから DB 接続情報を探す**

   手順3の `WorkingDirectory` を webapp パスとして:
   ```bash
   # 接続情報が書かれていそうなファイルを探す
   grep -rE '(db_host|DB_HOST|database_host|dsn|DataSourceName|mysql\.open|connectDB)' \
     <webapp-path> --include="*.go" --include="*.rb" --include="*.py" \
     --include="*.js" --include="*.ts" --include="*.php" --include="*.pl" \
     -l 2>/dev/null | head -5
   ```
   見つかったファイルを Read して接続情報（ホスト・ポート・ユーザー・パスワード・DB名）を抽出する。

   `.env` ファイルも確認する:
   ```bash
   find <webapp-path> -maxdepth 3 -name ".env" -o -name "*.env" 2>/dev/null
   ```

5. **DB の種別（ローカル / RDS / Aurora）を判定する**

   手順3・4で取得した DB ホスト名を基準に判定する（ローカルサービスの有無より優先）:
   - DB ホストが `*.cluster-*.rds.amazonaws.com` → **Aurora**
   - DB ホストが `*.rds.amazonaws.com` → **RDS**
   - DB ホストが他のプライベート IP → **別サーバーの MySQL**
   - DB ホストが `localhost` / `127.0.0.1` / 未設定 かつ手順2でローカル DB サービスあり → **ローカル MySQL/MariaDB**

   RDS / Aurora の場合、`setup-rds.sh` で種別を確認するために以下を実行する:
   ```bash
   mysql -h <db-host> -u <db-user> -p<db-pass> -N -e "SELECT @@version_comment;" 2>/dev/null
   ```

6. **静的ファイルのパスを特定する**

   アプリコードで静的ファイル配信パスを確認する:
   ```bash
   grep -rE '(static|public|assets|StaticFS|ServeFiles|send_file|sendfile)' \
     <webapp-path> --include="*.go" --include="*.rb" --include="*.py" \
     --include="*.js" --include="*.ts" --include="*.php" --include="*.pl" \
     --include="*.psgi" -l 2>/dev/null | head -5
   ```
   見つかったファイルを Read してパスを確認する。

7. **調査結果をまとめて推奨セットアップコマンドを提示する**

   すべての情報を整理し、以下の形式で出力する。
   DB 種別に応じてセットアップコマンドを切り替える。
   **出力するコマンドのプレースホルダー（`<host>` など）は、調査で取得した実際の値に置き換えて出力すること。**

## Output Format

```markdown
## ISUCON 環境サマリー

### サーバー
- OS: <distro> <version> (<arch>)
- Web サーバー: <nginx|h2o|apache> <version>
- アプリ: <言語> (サービス名: <name>, ポート: <port>)
- webapp パス: <path>
- 静的ファイルパス: <path>

### DB
- 種別: <ローカル MySQL|ローカル MariaDB|RDS MySQL|Aurora MySQL|PostgreSQL 等>
- ホスト: <host>
- ポート: <port>
- ユーザー: <user>
- パスワード: <password>
- DB 名: <dbname>

### 推奨セットアップコマンド

# このサーバーで実行
sudo bash scripts/setup-nginx.sh     # Web サーバーがある場合
sudo bash scripts/setup-tools.sh
sudo bash scripts/setup-app.sh

# DB セットアップ（ローカルの場合）
sudo bash scripts/setup-mysql.sh

# DB セットアップ（RDS / Aurora の場合）
DB_HOST=<host> DB_USER=<user> DB_PASS=<password> sudo bash scripts/setup-rds.sh
# slow_query_log が OFF の場合（パラメータグループ変更）:
# RDS_INSTANCE=<id> RDS_PARAM_GROUP=<group> DB_HOST=<host> DB_USER=<user> DB_PASS=<password> sudo bash scripts/setup-rds.sh --aws-cli
```
