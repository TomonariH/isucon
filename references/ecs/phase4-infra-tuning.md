# ECS/RDS Phase 4 Infra Tuning

ECS task definition / container image / RDS/Aurora parameter group を単体差分で評価する。

## Read First

- `$TOOL_REPO/references/ecs/goal-common.md`
- `$TOOL_REPO/references/phase-boundaries.md`

## Regulation Note

レギュレーションでスペック増強・インフラ構成変更が禁止の場合、task CPU/memory 増・Aurora インスタンス級上げ・ACU 上限引き上げ・reader/外部 cache/S3 等の追加・AZ 移動は封印し、アプリ改修と既存 parameter group の値 tuning に集中する。既存 reader endpoint への参照振り分けはアプリ改修として可、reader の追加は不可。CloudWatch メトリクスと Performance Insights は診断目的で使い、上記の封印された lever の根拠にしない。

## Baseline

```bash
bash $TOOL_REPO/scripts/ecs/bench-locked.sh --rebuild --analyze
bash $TOOL_REPO/scripts/score-log.sh <score> "ecs infra baseline"
```

## Candidates

1. RDS / Aurora parameter group を単体評価する。
   - `long_query_time=0` は分析用。最終構成には原則残さない。
   - `innodb_flush_log_at_trx_commit` / `sync_binlog` / connection cache 系は parameter group で変更する。
   - Aurora 注意: Aurora はストレージ層が durability を担うため、`innodb_flush_log_at_trx_commit` / `sync_binlog` の緩和は自前 MySQL ほど効かず、多くの場合ほぼ無効。Aurora ではここに時間をかけず、index / N+1 解消・接続設計・既存 reader endpoint への参照振り分け（アプリ改修）に振る。
   - Aurora は DB cluster parameter group と DB instance parameter group の両方を確認する。
   - `ApplyMethod=pending-reboot` の値は DB instance reboot が必要。Aurora cluster の場合も対象 instance ごとの再起動可否を確認する。
   - 変更前後の cluster parameter group / instance parameter group 値を `reports/ecs-infra-tuning.md` に記録する。

2. nginx config を image 差分として評価する。
   - nginx の LTSV 化は Phase1 の計測チェーン疎通ゲート（`references/ecs/phase1-survey.md`）で済ませている前提。Phase4 では LTSV 化そのものではなく、upstream keepalive / static file direct serving など純粋な性能調整に集中する。万一まだ LTSV でないなら、性能調整より先に LTSV 化して計測を成立させる。
   - upstream keepalive / static file direct serving は image 内 config 変更として扱う。
   - running container 内の `/etc/nginx` を直接編集しない。

3. ECS task sizing を単体評価する。
   - `scripts/ecs/analyze.sh` の CloudWatch メトリクス（Fargate CPU/Memory、Aurora CPU/接続数）を根拠にする。app CPU 飽和なら sizing/scale、Aurora 律速ならアプリ修正/DB tuning を優先する。
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

- RDS/Aurora parameter、nginx config、task sizing をまとめて変えること。
- Phase 6 のログ停止や pprof 削除をここで行うこと。
