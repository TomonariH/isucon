# ECS/RDS Phase 2 Improvement Loop

アプリ改善を ECS deploy 経由で評価する。

## Read First

- `$TOOL_REPO/references/ecs/goal-common.md`
- `$TOOL_REPO/references/agent-rules.md`
- `$TOOL_REPO/references/orchestration-rules.md`
- `$TOOL_REPO/references/phase-boundaries.md`

## Procedure

- 前提: baseline を取る前に、Phase1 の「計測チェーン疎通ゲート」（nginx LTSV / Aurora slow query or Performance Insights / 非空 analyze）を通過していること（`references/ecs/phase1-survey.md` の "Verify Measurement Chain (Phase2 入場ゲート)" 参照）。通過していなければ最初の analyze が空になるので、まず計測を直す。
- CloudWatch メトリクス / PI には publish 遅延（数分）がある。CPU / AAS / 接続数の正確な比較が要るときは、ベンチ完了の数分後に `BENCH_START_EPOCH=<bench epoch> bash scripts/ecs/analyze.sh` で再 analyze する（直後の値は窓の最新分が過小/n/a になりうる）。
- 公式 score の自動取得が未確定（P0-B / Phase1 待ち）の間は、`scripts/ecs/analyze.sh` の ALB `RequestCount`（window 合計）と `TargetResponseTime` p99、Performance Insights の Total DB Load(AAS) を**暫定ランキング指標**にして候補を一次選別する（多くの ISUCON は throughput 連動なので RequestCount 増 / p99 減 / AAS 減が代理になる）。RequestCount は **benchmark が実際に叩く ALB** のものを見る（公開 frontend ALB 経由で入る構成なら frontend ALB、backend を直叩きするなら backend ALB。`metrics.sh` は backend 既定で frontend は env があれば両方出す）。公式 score が取れたら `score-log.sh` で確定記録する。
- Performance Insights は 1 分粒度なので、60s 前後のベンチ 1 回では SQL 別 AAS が 1–2 datapoint でノイズに弱い。Top SQL のランキングを信頼するときはベンチを数回/長めに回すか、複数 analyze をまたいで傾向を見る。
- 候補を却下する場合は統合 branch を再 deploy して baseline 構成に戻してから次の候補を評価する（改悪 image を動かしたままにしない）。

1. app repo を確認し、統合 branch に移動する。
2. baseline を取る。

   ```bash
   bash $TOOL_REPO/scripts/ecs/bench-locked.sh --analyze
   bash $TOOL_REPO/scripts/score-log.sh <score> "ecs baseline"
   ```

3. `$TOOL_REPO/scripts/ecs/analyze.sh` の report を `/isucon-analyze` で読む。
4. 高・中インパクトの候補だけを抽出し、`improvement-log.sh candidate` で記録する。
5. 候補ごとに独立 branch / worktree を作る。
6. 修正ごとに image build / ECR push / ECS deploy / benchmark を実行する。SQS benchmark 環境では `BENCH_CMD='bash $TOOL_REPO/scripts/ecs/bench-sqs.sh'` にしておく。

   ```bash
   bash $TOOL_REPO/scripts/ecs/bench-locked.sh --rebuild --analyze
   ```

7. 採用する修正だけ統合 branch に merge し、merge 後も ECS deploy + benchmark で確認する。
8. score と採否を記録する。
9. 高・中インパクト提案がなくなるまで繰り返す。

## Fargate/Aurora 固有の優先候補

no-spec-change（スペック増強・インフラ構成変更が禁止）の構成では Phase4 の Aurora parameter 調整が痩せるため、Phase2 アプリ改修が主戦場になる。`/isucon-analyze` はまず次を起点に候補を出す。**許可レバー**（アプリ改修・既存リソース活用）に絞り、**封印レバー**は提案しない。

許可レバー（優先度の目安順）:

- N+1 解消・不要クエリ削減・covering index（`pi.sh` の Top SQL / slow query で律速 SQL を特定）。最も効く。
- **既存 Aurora reader endpoint への参照系クエリ振り分け**（read を reader へ。これはアプリ改修＝可。reader の*追加*は構成変更＝不可）。`AuroraReplicaLag` を `metrics.sh` で監視し、整合性 fail を避ける。
- 接続プール設計: Go の `SetMaxOpenConns` / `SetMaxIdleConns` / `ConnMaxLifetime` を **`desired count(task数) × pool ≤ Aurora max_connections`** に収め、リクエスト毎 connect を避ける。`metrics.sh` の `DatabaseConnections` / `TargetConnectionErrorCount` で確認。
- prepared statement / コネクション再利用、N+1 のバルク化・JOIN 化・キャッシュ（アプリ内 or 正データでない範囲）。
- 静的配信を frontend で完結させ、backend/app に届かせない（`RequestCount` の段間比較で素通りを確認）。
- nginx upstream keepalive / gzip など image 内 config（純粋なアプリ側チューニング。Phase4 と重複するものはどちらかで単体評価）。

封印レバー（このレギュレーションでは提案しない）:

- task CPU/memory 増、Aurora インスタンス級上げ、ACU 上限引き上げ（=スペック増強）。
- reader インスタンス追加、ElastiCache/Redis・S3 等の新規リソース追加、AZ 移動（=構成変更）。
- Aurora の `innodb_flush_log_at_trx_commit` / `sync_binlog` 緩和（Aurora ではストレージ層が durability を担い、ほぼ無効）。

## ECS-Specific Checks

- deploy 後に task definition revision / image tag が想定通りか確認する。
- `aws sts get-caller-identity` の account ID と ECR repository が想定通りか確認する。
- CloudWatch Logs が新 task の stream から取得できているか確認する。
- RDS connection 数が増えすぎていないか確認する。
- benchmark target が backend ALB URL になっているか確認する。
- SQS send-message の response と benchmark 側の messages を確認する。

## Forbidden

- running task 内だけを手で変更して採用扱いにすること。
- ECS service を通さず container を直接 restart すること。
- 複数候補を1つの image にまとめて評価すること。
