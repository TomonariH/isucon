# /isucon-pprof

Go アプリに pprof プロファイリングを追加し、ボトルネック関数を特定する。

## Steps

0. **前提条件を確認する**

   ホストに `go` コマンドが必要（`go tool pprof` を使うため）:
   ```bash
   go version || echo "not installed"
   ```

   入っていない場合はインストールする:
   ```bash
   sudo snap install go --classic   # 推奨（最新版）
   # または
   sudo apt install golang-go       # 古めのバージョンでも動く
   ```

   **`scripts/env.sh` を Read して環境情報を把握する**

   確認する変数: `ISUCON_RUNTIME`（docker|systemd）・`ISUCON_WEBAPP_DIR`・`DOCKER_COMPOSE_DIR`・`DOCKER_COMPOSE_FILE`・`DOCKER_COMPOSE_FILE_ARGS`・`REBUILD_CMD`

1. **Go アプリの main ファイルを見つける**

   ```bash
   find "$ISUCON_WEBAPP_DIR" -name "main.go" -o -name "app.go" | head -5
   ```

2. **pprof エンドポイントを追加する**

   **Docker Compose 環境**: ホストから `go tool pprof` で直接取得するため `0.0.0.0:6060` にバインドする。

   **systemd 環境**: `127.0.0.1:6060` でよい（ホストから直接アクセス可能）。

   ```go
   import _ "net/http/pprof"

   // main() の中（ListenAndServe の直前）
   // Docker: "0.0.0.0:6060"、systemd: "127.0.0.1:6060"
   go func() { log.Println(http.ListenAndServe("0.0.0.0:6060", nil)) }()
   ```

   **Docker Compose 環境のみ**: ホストの localhost にポートを露出する compose override を追加する。
   `<DOCKER_COMPOSE_DIR>/docker-compose.pprof.yml` を作成する:

   ```yaml
   # docker-compose.pprof.yml — pprof 用ポート公開（競技終了後に削除）
   services:
     <app-service>:
       ports:
         - "127.0.0.1:6060:6060"
   ```

   `scripts/env.sh` の `DOCKER_COMPOSE_FILE_ARGS` に `-f <DOCKER_COMPOSE_DIR>/docker-compose.pprof.yml` を追加し、`REBUILD_CMD` が同じ `DOCKER_COMPOSE_FILE_ARGS` を使っていることを確認する。

3. **アプリをビルドして再起動する**

   `REBUILD_CMD` が空でなければそのまま実行する:
   ```bash
   eval "$REBUILD_CMD"
   ```

   `REBUILD_CMD` が空の場合は runtime を見て手動で実行する:

   **systemd 環境**:
   ```bash
   systemctl list-units --type=service | grep -E 'isu|go|app'
   go build -o app . && sudo systemctl restart <サービス名>
   ```

   **Docker Compose 環境**: `DOCKER_COMPOSE_FILE_ARGS` に pprof override も含めて起動する:
   ```bash
   docker compose $DOCKER_COMPOSE_FILE_ARGS up --build -d <app-service>
   ```

4. **pprof エンドポイントが起動しているか確認する**

   コンテナ内に curl/wget がない場合が多いので `/proc/net/tcp` で確認する:
   ```bash
   # 6060 = 0x17AC。LISTEN(0A) 状態の行が出れば OK
   docker exec <app-container> sh -c 'cat /proc/net/tcp | grep 17AC'
   ```

   systemd 環境:
   ```bash
   curl -s http://127.0.0.1:6060/debug/pprof/ | head -3
   ```

5. **ベンチマーク中にプロファイルを取得する**

   ベンチマークを起動したら、別ターミナルで実行する（負荷がかかった状態でのプロファイルが有効）:

   ```bash
   # CPU プロファイル（30秒間）
   go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30

   # メモリ（ヒープ）プロファイル
   go tool pprof http://localhost:6060/debug/pprof/heap
   ```

6. **結果を分析する**

   pprof の対話シェルで:
   ```
   (pprof) top10        # CPU 時間の上位10関数
   (pprof) top10 -cum   # 累積 CPU 時間（呼び出し元を含む）の上位10
   (pprof) list <func>  # 関数のソースコードと CPU 時間の内訳
   ```

   ブラウザ UI で確認する場合:
   ```bash
   go tool pprof -http=:8081 http://localhost:6060/debug/pprof/profile?seconds=30
   # http://localhost:8081 でフレームグラフを確認
   ```

7. **取得したプロファイルデータを読んで改善提案を出す**

   pprof の `top10` 出力をこのチャットにペーストすると、
   どの関数がボトルネックかを分析して改善案を提示する。

   よくあるパターン:
   - `database/sql.(*Stmt).QueryContext` の比率が高い → クエリ最適化
   - `encoding/json.Marshal` が多い → キャッシュまたは構造体の最適化
   - `sync.(*Mutex).Lock` が多い → ロック競合、sync.RWMutex に変更
   - `runtime.mallocgc` が多い → メモリアロケーション削減、オブジェクトプール

## Output Format

```markdown
## pprof 分析結果

### 環境
- エンドポイント: http://localhost:6060/debug/pprof/
- 取得: CPU 30秒 / Heap

### 上位ボトルネック関数
| 順位 | 関数 | CPU 時間 | 推測される原因 |
|------|------|---------|--------------|
| 1 | ... | XX% | ... |

### 改善提案
1. [高インパクト] ...
```
