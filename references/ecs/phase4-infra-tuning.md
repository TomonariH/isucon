# ECS/RDS Phase 4 Infra Tuning

ECS task definition / container image / RDS parameter group を単体差分で評価する。

## Read First

- `$TOOL_REPO/references/ecs/goal-common.md`
- `$TOOL_REPO/references/phase-boundaries.md`

## Baseline

```bash
bash $TOOL_REPO/scripts/ecs/bench-locked.sh --rebuild --analyze
bash $TOOL_REPO/scripts/score-log.sh <score> "ecs infra baseline"
```

## Candidates

1. RDS parameter group を単体評価する。
   - `long_query_time=0` は分析用。最終構成には原則残さない。
   - `innodb_flush_log_at_trx_commit` / `sync_binlog` / connection cache 系は parameter group で変更する。
   - `ApplyMethod=pending-reboot` の値は RDS reboot が必要。再起動可否を確認する。
   - 変更前後の parameter group 値を `reports/ecs-infra-tuning.md` に記録する。

2. nginx config を image 差分として評価する。
   - nginx container stdout が LTSV でないなら LTSV 化を最優先する。
   - upstream keepalive / static file direct serving は image 内 config 変更として扱う。
   - running container 内の `/etc/nginx` を直接編集しない。

3. ECS task sizing を単体評価する。
   - task CPU / memory を task definition revision として変更する。
   - Fargate の場合は許可される CPU/memory 組み合わせに従う。
   - EC2 launch type の場合は container instance の余力も確認する。

4. cache container / external cache 設定を評価する。
   - memcached / Redis が task 内 container なのか外部 service なのかを確認する。
   - 正データでない場合だけ cache 用 template の考え方を反映する。

## Verification

- `aws ecs describe-services` で deployment が stable であること。
- `aws ecs describe-tasks` で expected task definition revision が動いていること。
- `scripts/ecs/analyze.sh` で nginx stdout と RDS slow query が取れていること。
- fail 時は ECS events / CloudWatch Logs / RDS slow query を確認する。

## Forbidden

- RDS parameter、nginx config、task sizing をまとめて変えること。
- Phase 6 のログ停止や pprof 削除をここで行うこと。
