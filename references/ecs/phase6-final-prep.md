# ECS/RDS Phase 6 Final Prep

ECS/RDS の最終提出用構成を固定し、不要な分析設定を外す。

## Read First

- `$TOOL_REPO/references/ecs/goal-common.md`
- `$TOOL_REPO/references/phase-boundaries.md`

## Procedure

1. 最終構成を一覧化する。
   - app commit
   - Docker image tag / digest
   - ECS task definition revision
   - ECS service desired count
   - task CPU / memory
   - RDS/Aurora cluster parameter group / instance parameter group
   - security group
   - CloudWatch log group

2. 分析用設定を外す。
   - pprof import / goroutine / port
   - temporary security group / route
   - RDS/Aurora `long_query_time=0` や `slow_query_log=1` が最終スコアに不要なら parameter group で戻す
   - nginx access log を止める場合は、分析が終わってから image/config に反映する

3. 最終 image を build/push/deploy する。

   ```bash
   bash $TOOL_REPO/scripts/ecs/bench-locked.sh --rebuild --analyze
   ```

4. service stable と task revision を確認する。

   ```bash
   aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
   aws ecs describe-tasks --cluster "$ECS_CLUSTER" --tasks $(aws ecs list-tasks --cluster "$ECS_CLUSTER" --service-name "$ECS_SERVICE" --query 'taskArns[0]' --output text)
   ```

5. final benchmark を実行し、pass / score / messages を記録する。
6. 可能なら ECS service の再 deployment または task replacement 後にも pass することを確認する。
7. `reports/ecs-final-prep.md` に最終メモを残す。

## Forbidden

- 未評価の image / task definition / RDS/Aurora parameter を最終構成にすること。
- pprof や unrestricted debug port を残すこと。
- task 内手作業だけで成立する設定を最終構成にすること。
