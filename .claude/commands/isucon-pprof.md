# /isucon-pprof

Go アプリに pprof プロファイリングを追加し、ボトルネック関数を特定する。

## Steps

1. **Go アプリの main ファイルを見つける**

   ```bash
   find . -name "main.go" -o -name "app.go" | head -5
   ```

2. **pprof エンドポイントを追加する**

   `templates/go-pprof.snippet` を参考に、アプリの main.go に追加する。
   
   **パターン A: 標準 http.ServeMux を使っている場合**
   ```go
   import (
     "log"
     "net/http"
     _ "net/http/pprof"
   )
   
   // main() の中
   go func() { log.Println(http.ListenAndServe("127.0.0.1:6060", nil)) }()
   ```
   
   **パターン B: echo / gin / chi 独自 mux の場合**
   ```go
   // echo
   e.GET("/debug/pprof/*", echo.WrapHandler(http.DefaultServeMux))
   
   // gin
   pprof.Register(router)  // gin-contrib/pprof
   
   // chi
   r.Mount("/debug", middleware.Profiler())
   ```

3. **アプリをビルドして再起動する**

   **systemd 環境の場合**:
   ```bash
   # サービス名を確認
   systemctl list-units --type=service | grep -E 'isu|go|app'

   # ビルドして再起動（確認したサービス名を使う）
   go build -o app . && sudo systemctl restart <サービス名>
   ```

   **Docker Compose 環境の場合**:
   ```bash
   # compose.yml があるディレクトリで実行
   # アプリサービス名を確認
   docker compose ps

   # ビルドして再起動（アプリのソースが volume マウントされている場合）
   go build -o app . && docker compose restart <app-service>

   # Dockerfile でビルドしている場合（Go など）
   docker compose up --build -d <app-service>
   ```

   Docker Compose 環境で pprof を取得する場合は、むやみに `ports: "6060:6060"` を公開しない。
   まず `docker compose exec <app-service> curl -s http://127.0.0.1:6060/debug/pprof/goroutine?debug=1` でコンテナ内から確認する。
   ホストから取得する必要がある場合のみ、SSH port-forward または localhost 限定のポート公開を使う。

4. **ベンチマーク中にプロファイルを取得する**

   ベンチマークが走っている最中に実行する（負荷がかかった状態でのプロファイルが有効）:

   ```bash
   # CPU プロファイル（30秒間）
   go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30
   
   # メモリ（ヒープ）プロファイル
   go tool pprof http://localhost:6060/debug/pprof/heap
   
   # goroutine の状態（ブロックの確認）
   curl -s http://localhost:6060/debug/pprof/goroutine?debug=1 | head -50
   ```

5. **結果を分析する**

   pprof の対話シェルで:
   ```
   (pprof) top10        # CPU 時間の上位10関数
   (pprof) top10 -cum   # 累積 CPU 時間（呼び出し元を含む）の上位10
   (pprof) list <func>  # 関数のソースコードと CPU 時間の内訳
   (pprof) web          # ブラウザでフレームグラフを開く（要 graphviz）
   ```

   ブラウザ UI で確認する場合:
   ```bash
   go tool pprof -http=:8081 http://localhost:6060/debug/pprof/profile?seconds=30
   # http://localhost:8081 でフレームグラフを確認
   ```

6. **取得したプロファイルデータを読んで改善提案を出す**

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
