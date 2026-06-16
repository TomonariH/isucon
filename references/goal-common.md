# Goal Common Rules

ISUCON の `/goal` で使う共通ルール。Phase 固有の手順より優先して読む。

## Environment

- 最初に `$TOOL_REPO/scripts/env.sh` を読む。存在する場合は `source "$TOOL_REPO/scripts/env.sh"` して、少なくとも次を確認する:
  - `TOOL_REPO`
  - `ISUCON_RUNTIME`
  - `ISUCON_WEBAPP_DIR`
  - `DOCKER_COMPOSE_DIR`
  - `DOCKER_COMPOSE_FILE`
  - `DOCKER_COMPOSE_FILE_ARGS`
  - `BENCH_CMD`
  - `REBUILD_CMD`
- app リポジトリは原則 `APP_REPO="$(dirname "$ISUCON_WEBAPP_DIR")"` とする。
- 統合先ブランチは原則 `$APP_REPO` の `feature/isucon-work` とする。

## Compact / Resume Safety

compact、中断、別 turn からの再開後は、作業を続ける前に必ず次を確認する。

1. 最新のユーザー指示を読む。特に「push して」「セルフレビューして」「Phase 4 で Phase 6 をしない」などの継続条件を確認する。
2. `git status --short --branch` を確認し、未コミット変更・未追跡ファイル・現在 branch を把握する。
3. `$TOOL_REPO/scripts/env.sh`、`reports/survey.md`、最新 `reports/*.md` を必要に応じて読み直す。
4. 現在実行中の Phase reference と、この `goal-common.md` を読み直す。
5. 未完了タスク、禁止事項、検証方法、push 要否を整理してから再開する。
6. compact 前の指示が不明、または相互に矛盾して見える場合は、推測で進めずユーザーに確認する。

この確認は Phase 固有手順より優先する。

## Benchmark Exclusivity

- rebuild / restart / benchmark は必ず `$TOOL_REPO/scripts/bench-locked.sh` で実行する。
- benchmark は常に1つだけ実行する。他 goal・他エージェントの rebuild / restart / benchmark と同時に実行しない。
- 変更評価では原則 `$TOOL_REPO/scripts/bench-locked.sh --rebuild` を使う。
- ベンチ後は必要に応じて `$TOOL_REPO/scripts/analyze.sh` を実行し、分析材料を残す。
- スコアは `$TOOL_REPO/scripts/score-log.sh` で記録する。

## Failure Diagnosis

fail が出た場合、即ロールバック・即却下しない。

必ず次を確認し、ログに基づいて正確な原因を特定する:

- `bench-locked.sh` の出力 `messages`
- benchmark stdout / stderr
- app ログ
- nginx ログ
- MySQL ログ
- access log / slow query
- Docker Compose の場合は対象 service の `docker compose logs`

原因を推測で決めない。次のような観点で、観測したログ・エラーメッセージ・再現コマンドを記録する:

- 静的ファイル不整合
- セッション不整合
- DB 接続エラー
- initialize 漏れ
- nginx 直配信 path 不整合
- Docker Compose override の不足
- app 複数台化時の host port 衝突

原因がその修正内で解消できる場合は、同じ branch / worktree で追加修正して再評価する。ログから原因を特定できない、または修正しても fail が解消しない場合のみ、その候補を採用対象から外す。

## Git Safety

- `git reset --hard` などの破壊的操作は禁止。
- unrelated changes を巻き戻さない。
- 未採用 branch / worktree は勝手に削除しない。残す、後で消す、再評価する、の判断を記録する。
- 採用した変更は commit を残す。squash は原則しない。

## Recording

改善候補、採否、スコア、fail 原因、cleanup 判断は記録する。

- アプリ改善: `$TOOL_REPO/scripts/improvement-log.sh`
- スコア: `$TOOL_REPO/scripts/score-log.sh`
- ミドルウェア評価: `$TOOL_REPO/reports/infra-tuning.md`
- 最終整備: `$TOOL_REPO/reports/final-prep.md`
