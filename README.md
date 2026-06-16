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
  lib-docker.sh     # Docker Compose 環境向け helper（compose file / service 検出）
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
references/
  goal-common.md            # /goal 共通ルール（env, bench lock, fail診断, git安全）
  agent-rules.md            # エージェント別ルール（Claude Code / Codex / 共通）
  orchestration-rules.md    # 複数エージェント・worktree・merge採否ルール
  phase-boundaries.md       # Phase の責務境界
  goals/                    # Phase 別 /goal 手順
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

このフェーズでは、複数エージェントで改善候補を並列実装し、改善したものだけを統合する。詳細手順は reference に分割しているため、Claude Code には次の短い prompt を投げる。

```text
/goal
まずツールリポジトリで `source scripts/env.sh` してから、以下を順に読み、Phase 2 の改善ループを実行してください。

- $TOOL_REPO/references/goal-common.md
- $TOOL_REPO/references/agent-rules.md
- $TOOL_REPO/references/orchestration-rules.md
- $TOOL_REPO/references/phase-boundaries.md
- $TOOL_REPO/references/goals/phase2-improvement-loop.md
```

---

### Phase 3 — pprof サイクル

改善ループのスコアが伸び悩んだとき、alp・スロークエリでは見えないアプリ内部のCPUホットスポットを特定して修正する。

```text
/goal
まずツールリポジトリで `source scripts/env.sh` してから、以下を順に読み、Phase 3 の pprof サイクルを実行してください。

- $TOOL_REPO/references/goal-common.md
- $TOOL_REPO/references/agent-rules.md
- $TOOL_REPO/references/orchestration-rules.md
- $TOOL_REPO/references/phase-boundaries.md
- $TOOL_REPO/references/goals/phase3-pprof-cycle.md
```

---

### Phase 4 — ミドルウェア秘伝のタレ評価

アプリ改善と pprof 分析が一巡したら、MySQL / nginx / memcached / Redis の定番設定を単体差分で評価する。テンプレートは `templates/` に分割してあるので、効いたものだけ残す。

```text
/goal
まずツールリポジトリで `source scripts/env.sh` してから、以下を順に読み、Phase 4 のミドルウェア秘伝のタレ評価を実行してください。

- $TOOL_REPO/references/goal-common.md
- $TOOL_REPO/references/agent-rules.md
- $TOOL_REPO/references/phase-boundaries.md
- $TOOL_REPO/references/goals/phase4-infra-tuning.md
```

---

### Phase 5 — サーバー分割

1台構成でアプリ改善・pprof・ミドルウェア調整が一巡し、CPU / メモリ / DB のどれかが明確に上限に近い場合だけ、複数台構成を検討する。サーバー分割は長期ループではなく、まず `/isucon-multiserver` スキルで「最新レポートに基づく分割案・手順・実施可能なローカル修正」を出す。

```text
/isucon-multiserver
```

このスキルが行うこと:
- `scripts/env.sh`、最新 `reports/*.md`、`reports/scores.md`、`reports/survey.md` を読み、最新ボトルネックから最適な分割案を出す
- 現在のISUCONレギュレーション、利用可能サーバー、入口URL、Docker Compose / systemd / RDS などの実行環境を確認する
- 手順提示に必要なIP、SSH可否、sudo権限、DB移行、画像/セッション共有などが不明なら、調査またはユーザーへの確認を行う
- nginx upstream、MySQL外部接続、app/cache/静的ファイル共有、分散環境でのログ収集、ロールバック手順を提示する
- スキルが実行されているサーバー内で安全に実施できる変更があれば、新規ブランチを作成して適用・検証・commit する

実際に複数案をベンチで反復評価する場合だけ、`/isucon-multiserver` の出力を正本として別途 `/goal` を使う。

---

### Phase 6 — 最終提出用のサーバー整備

提出直前は、分析用の重いログ・pprof・一時ファイル・未採用設定を外し、再起動後も同じ構成で起動することを確認する。ここでは新しい最適化を増やさず、採用済み変更の固定と事故防止に集中する。

```text
/goal
まずツールリポジトリで `source scripts/env.sh` してから、以下を順に読み、Phase 6 の最終提出用サーバー整備を実行してください。

- $TOOL_REPO/references/goal-common.md
- $TOOL_REPO/references/agent-rules.md
- $TOOL_REPO/references/phase-boundaries.md
- $TOOL_REPO/references/goals/phase6-final-prep.md
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
