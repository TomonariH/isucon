# AGENTS.md

Guidance for AI agents when working in this repository.

## Repository Purpose

このリポジトリは ISUCON 競技向けのスキル、スクリプト、テンプレート、運用 reference を管理する。
競技本番で再利用できる汎用手順を保つことを優先し、特定の練習環境・競技回・サーバー構成に依存する情報はここに固定しない。

## Context Rules

- 実行環境は推測しない。作業前に `scripts/env.sh`、`reports/survey.md`、最新 `reports/*.md`、対象アプリの設定を読む。
- private-isu などの練習環境固有のパス、DB名、ベンチコマンド、既知ボトルネックを前提にしない。
- ISUCON のレギュレーション、サーバー台数、入口 URL、再起動方法は競技ごとに変わる。ローカル資料がなければユーザーに確認する。
- `/goal` の手順は README から参照される `references/` を正本にする。
- Phase の責務境界を守る。特に Phase 4 で Phase 6 の最終提出作業を実施しない。

## Safety Rules

- benchmark / rebuild / restart は `scripts/bench-locked.sh` 経由で直列化する。
- fail が出た場合は推測で戻さず、benchmark messages、app/nginx/MySQL/cache ログ、access log、slow query から原因を特定する。
- `git reset --hard` などの破壊的操作は禁止。
- ユーザーや他エージェントの未コミット変更を巻き戻さない。
- 本番環境に影響する変更は、根拠、検証方法、ロールバック方法を明確にする。

## Repository Map

- `scripts/`: 環境調査、分析、ベンチ排他、スコア記録、セットアップ用 shell
- `templates/`: nginx / MySQL / Redis / memcached / pprof などの設定テンプレート
- `references/`: `/goal` 共通ルール、エージェントルール、オーケストレーション、Phase 別手順
- `.claude/commands/`: Claude Code 用 ISUCON スキル定義
- `.codex/skills/`: Codex 用 skill wrapper
- `reports/`: 調査・分析・評価結果の出力先

## Development Notes

- 汎用性を壊す環境固有値は README / AGENTS / CLAUDE に追加しない。
- 環境固有の結果は `reports/` に記録する。
- 競技手順の共通化は `references/`、実行可能な補助処理は `scripts/`、設定例は `templates/` に置く。
