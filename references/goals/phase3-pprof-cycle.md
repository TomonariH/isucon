# Phase 3 pprof Cycle

alp・slow query では見えないアプリ内部の CPU ホットスポットを pprof で特定し、改善する。

## Read First

- `$TOOL_REPO/references/goal-common.md`
- `$TOOL_REPO/references/agent-rules.md`
- `$TOOL_REPO/references/orchestration-rules.md`
- `$TOOL_REPO/references/phase-boundaries.md`
- `/isucon-pprof` スキル

## Procedure

0. pprof が未導入なら `/isucon-pprof` スキルに従って導入する。
   - Go アプリの main ファイルを探す。
   - `import _ "net/http/pprof"` と pprof 用 `ListenAndServe` が存在するか確認する。
   - Docker Compose 環境では pprof 用 compose override と host port 公開を確認する。
   - 変更があった場合だけ `$TOOL_REPO/scripts/bench-locked.sh --rebuild` で再ビルドする。
1. ベンチマークを lock 経由でバックグラウンド起動し、同時に CPU profile を取得する。

   ```bash
   PPROF_OUT="$TOOL_REPO/reports/pprof-$(date +%Y%m%d-%H%M%S)"
   "$TOOL_REPO/scripts/bench-locked.sh" --no-reset-logs > "${PPROF_OUT}-bench.txt" 2>&1 &
   BENCH_PID=$!
   sleep 5
   curl -s "http://localhost:6060/debug/pprof/profile?seconds=25" -o "${PPROF_OUT}.pprof"
   wait $BENCH_PID
   ```

2. profile をテキスト化して保存する。

   ```bash
   go tool pprof -top "${PPROF_OUT}.pprof" > "${PPROF_OUT}-top.txt"
   echo "--- cum ---" >> "${PPROF_OUT}-top.txt"
   go tool pprof -top -cum "${PPROF_OUT}.pprof" >> "${PPROF_OUT}-top.txt"
   ```

3. `/isucon-analyze ${PPROF_OUT}-top.txt` を呼び出して、alp / slow query / pprof を合わせて分析する。
4. 高・中インパクトの提案を抽出する。小インパクトのみなら終了する。
5. `$TOOL_REPO/references/orchestration-rules.md` に従い、提案1つにつき1つの独立 branch / worktree で並列修正する。
6. 各修正を `$TOOL_REPO/scripts/bench-locked.sh --rebuild` で評価し、改善が確認できたものだけ `feature/isucon-work` に merge する。
7. merge 後は `$TOOL_REPO/scripts/score-log.sh` でスコアを記録する。
8. 全提案を評価したら手順1に戻る。

## Forbidden

- ベンチマーク実行中の rebuild / restart。
- 複数提案を1つの worktree にまとめること。
- Phase 6 の最終提出作業を実施すること。
