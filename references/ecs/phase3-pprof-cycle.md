# ECS/RDS Phase 3 pprof Cycle

ECS 環境で pprof を取得し、アプリ内部の CPU / heap ボトルネックを特定する。

## Read First

- `$TOOL_REPO/references/ecs/goal-common.md`
- `/isucon-pprof` は systemd/docker-compose 前提のため、ECS ではこの手順を優先する。

## Procedure

1. Go アプリに `net/http/pprof` endpoint を追加する。
   - container 内では `127.0.0.1:6060` で十分な場合がある。
   - task IP / 一時公開で外から取る場合は `0.0.0.0:6060` が必要。
2. pprof port の到達方法を決める。
   - 推奨: ECS Exec で container 内から取得
   - 次点: 作業用 EC2 から task IP に接続
   - 例外: 一時 security group / temporary route で公開
3. pprof 入り image を deploy する。

   ```bash
   bash $TOOL_REPO/scripts/ecs/bench-locked.sh --rebuild
   ```

4. benchmark と同時に profile を取得する。

   URL で取れる場合:

   ```bash
   bash $TOOL_REPO/scripts/ecs/bench-locked.sh --no-reset-logs &
   PPROF_URL='http://<reachable-host>:6060/debug/pprof/profile' bash $TOOL_REPO/scripts/ecs/pprof.sh
   wait
   ```

   ECS Exec で取る場合は `scripts/ecs/pprof.sh` が表示する command を使い、container 内で `curl` する。

5. `reports/pprof-*-top.txt` と ECS analysis report を合わせて `/isucon-analyze` に渡す。
6. 高・中インパクトの改善だけを Phase 2 と同じ deploy/benchmark loop で評価する。

## Phase 6 Handoff

- pprof import / goroutine
- pprof port
- temporary security group / route
- ECS Exec 前提の一時設定

これらは Phase 6 で削除対象として記録する。
