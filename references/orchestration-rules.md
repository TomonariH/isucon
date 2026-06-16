# Orchestration Rules

複数エージェント・複数 branch / worktree で改善候補を評価するときのルール。

## Roles

メインエージェント:

- 候補抽出
- branch / worktree 作成
- 実装担当への割り当て
- rebuild / restart
- benchmark
- 採否判断
- merge
- 記録

サブエージェント:

- 割り当てられた1候補・1 branch / worktree のみ編集する
- コード修正、ローカルテスト、commit 作成まで行う
- rebuild / restart、benchmark、merge は実行しない

## Parallelism

- 実装の同時実行数は最大5件まで。
- ファイルや領域でまとめず、提案項目1つにつき1つの独立 branch / worktree に分ける。
- 複数提案を1つの worktree にまとめない。
- benchmark は直列化する。並列実行しない。
- ECS では bench は `bench-locked.sh` の flock で直列だが、候補ごとの image build / ECR push は worktree 並列で先行実行しておける。これで bench 待ち行列の回転を上げられる（ただし deploy + bench 自体は 1 つずつ）。

## Candidate Selection

- `/isucon-analyze` や pprof 結果から、高インパクト・中インパクトの提案だけを候補にする。
- 小インパクトのみになったら、その loop は終了する。
- 候補ID、インパクト、難易度、予定 branch、改善方法を記録する。

## Evaluation

- 各修正 branch ごとに `$TOOL_REPO/scripts/bench-locked.sh --rebuild` で評価する。
- pass し、基準スコアより明確に改善した修正だけを merge 対象にする。
- fail が出た場合は `$TOOL_REPO/references/goal-common.md` の Failure Diagnosis に従う。

## Merge

- merge は `$APP_REPO` の `feature/isucon-work` に対して行う。
- merge 後は `$TOOL_REPO/scripts/bench-locked.sh --rebuild` を実行する。
- pass し、スコア改善が維持される場合は merge を確定する。
- merge 後に fail した場合、またはスコア改善が消えた場合は即 revert しない。まず conflict 解消ミス・実装バグ・設定漏れ・deploy 対象ミスと、throughput 増による次ボトルネック露出を切り分ける。
- conflict 解消が不確実、fail 原因がその修正内にあり解消できない、または実装バグで改善根拠が消えた場合は、その修正を採用しない。
- 単体では改善し、merge 後に別リソースの飽和や別ボトルネックが露出しただけなら、暫定 baseline として扱い次のボトルネック解消候補を評価する。最終的に best-known 構成を超えない場合だけ、提出前に戻す候補として記録する。
