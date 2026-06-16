# ECS/RDS Phase 5 Scale

ECS service の desired count、task size、target 方式を評価する。task 数の上限が 3 と分かっている場合は、1 -> 2 -> 3 の順で単体評価する。

## Read First

- `$TOOL_REPO/references/ecs/goal-common.md`
- `$TOOL_REPO/references/phase-boundaries.md`

## Regulation Note

レギュレーションでスペック増強・インフラ構成変更が禁止の場合、task CPU/memory 増・Aurora インスタンス級上げ・ACU 上限引き上げ・reader/外部 cache/S3 等の追加・AZ 移動は封印し、アプリ改修と既存 parameter group の値 tuning に集中する。既存 reader endpoint への参照振り分けはアプリ改修として可、reader の追加は不可。この Phase の desired count / task size 変更も封印対象に含まれる場合があるため、評価前にレギュレーションを確認する。

なお desired count（台数）増が「スペック増強」に当たるかはレギュレーション次第である。垂直増強（task CPU/memory・インスタンス級上げ）が禁止でも、水平スケール（台数増）は許可される大会が多い。ただし必ずレギュレーションで確認してから行い、確認できなければ封印する。

## Preconditions

- app が stateless か確認する。
- local filesystem upload / image / session 依存がある場合、desired count を増やす前に共有化する。
- RDS connection 上限と slow query を確認する。
- `scripts/ecs/analyze.sh` の CloudWatch メトリクスで、scale 前の律速箇所を確認する。Fargate CPU が飽和していれば desired count 増で改善余地があり、Aurora CPU/DatabaseConnections が先に飽和するなら scale しても DB で頭打ちになる。
- backend ALB 経由の benchmark になっていることを確認する。task direct URL のまま scale 評価しない。

## Procedure

1. 現在の service と task を記録する。

   ```bash
   aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
   aws ecs list-tasks --cluster "$ECS_CLUSTER" --service-name "$ECS_SERVICE"
   ```

2. desired count を 1 つずつ評価する。上限が 3 の場合は 2、3 の順に試す。

   ```bash
   aws ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --desired-count 2
   aws ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
   bash $TOOL_REPO/scripts/ecs/bench-locked.sh --analyze
   ```

3. backend ALB の target health が全 task で healthy になっているか確認する。

   ```bash
   aws elbv2 describe-target-health --target-group-arn <backend-target-group-arn>
   ```

4. DB が詰まる場合は desired count を戻し、アプリ改善または RDS tuning を優先する。
5. 採用/却下と理由を `reports/ecs-scale.md` に記録する。

## Rollback

```bash
aws ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --desired-count <previous>
aws ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
```
