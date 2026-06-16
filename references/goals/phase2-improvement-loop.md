# Phase 2 Improvement Loop

競技中の改善 loop を実行する。

## Read First

- `$TOOL_REPO/references/goal-common.md`
- `$TOOL_REPO/references/agent-rules.md`
- `$TOOL_REPO/references/orchestration-rules.md`
- `$TOOL_REPO/references/phase-boundaries.md`

## Procedure

1. `APP_REPO="$(dirname "$ISUCON_WEBAPP_DIR")"` を設定し、`$APP_REPO` の `feature/isucon-work` に移動する。
2. `$TOOL_REPO/scripts/bench-locked.sh` を1回実行し、現在の基準スコアを確認する。
3. `$TOOL_REPO/scripts/analyze.sh` を実行し、その結果を `/isucon-analyze` スキルで分析する。
4. `/isucon-analyze` の結果から、高インパクト・中インパクトの提案だけを抽出する。
5. 抽出した候補を、候補ごとに `$TOOL_REPO/scripts/improvement-log.sh candidate ...` で記録する。
6. 高・中インパクトの提案がなければ終了する。
7. `$TOOL_REPO/references/orchestration-rules.md` に従い、提案1つにつき1つの独立 branch / worktree で並列修正する。
8. 各修正 branch を `$TOOL_REPO/scripts/bench-locked.sh --rebuild` で評価する。
9. 採用する修正だけ `feature/isucon-work` に merge し、merge 後も `$TOOL_REPO/scripts/bench-locked.sh --rebuild` で確認する。
10. merge 後、改善スコアを `$TOOL_REPO/scripts/score-log.sh` で記録する。
11. 全ての高・中インパクト提案を評価し終えたら、手順2に戻る。
12. `/isucon-analyze` の結果が小インパクトのみになるまで継続する。

## Stop Conditions

- 高・中インパクトの提案が存在しない。
- fail 原因がログから特定できず、修正継続の根拠がない。
- benchmark や rebuild の排他制御が崩れている。

## Forbidden

- 複数提案を1つの worktree にまとめること。
- サブエージェントが rebuild / restart / benchmark / merge を実行すること。
- fail を推測でロールバックすること。
