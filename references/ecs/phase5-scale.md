# ECS/RDS Phase 5 Scale

ECS service の desired count、task size、target 方式を評価する。

## Read First

- `$TOOL_REPO/references/ecs/goal-common.md`
- `$TOOL_REPO/references/phase-boundaries.md`

## Preconditions

- app が stateless か確認する。
- local filesystem upload / image / session 依存がある場合、desired count を増やす前に共有化する。
- RDS connection 上限と slow query を確認する。
- task direct benchmark の場合、複数 task にどう流すかを確認する。

## Procedure

1. 現在の service と task を記録する。

   ```bash
   aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
   aws ecs list-tasks --cluster "$ECS_CLUSTER" --service-name "$ECS_SERVICE"
   ```

2. desired count を 1 つずつ評価する。

   ```bash
   aws ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --desired-count 2
   aws ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
   bash $TOOL_REPO/scripts/ecs/bench-locked.sh --analyze
   ```

3. task direct 入口の場合は、ベンチ対象が特定 task だけに固定されていないか確認する。
4. DB が詰まる場合は desired count を戻し、アプリ改善または RDS tuning を優先する。
5. 採用/却下と理由を `reports/ecs-scale.md` に記録する。

## Rollback

```bash
aws ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --desired-count <previous>
aws ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
```
