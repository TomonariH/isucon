# Agent Rules

エージェントごとの責務と制約。`/goal` の Phase 手順とあわせて読む。

## Claude Code

- README の `/goal` prompt では、該当 Phase の reference と共通 reference を必ず読んでから実行する。
- `/isucon-analyze`、`/isucon-pprof`、`/isucon-multiserver` などのスキルが指定されている場合は、そのスキルを正本にする。
- compact が入っても復元できるよう、作業中の前提・採否・次アクションは report または log に残す。
- サブエージェントへ実装を委譲する場合も、rebuild / restart / benchmark / merge はメインエージェントだけが実行する。

## Codex

- ユーザーが実装や修正を求めた場合、提案だけで止めず、可能な範囲でファイル編集・検証まで行う。
- 既存の未コミット変更はユーザーまたは他エージェントの作業として扱い、明示依頼なしに戻さない。
- ファイル編集は原則 `apply_patch` を使う。
- repo 内の skill を使う必要がある場合は、該当 `SKILL.md` を最後まで読んでから実行する。
- benchmark や長い loop は、ユーザーが明示した場合だけ実行する。

## Shared

- 手順が不明な場合は、まずローカルの `reports/`、`scripts/env.sh`、競技 README、設定ファイルから調査する。
- 安全性に関わる情報が調査できない場合だけ、ユーザーへ確認する。
- 推測で本番系の設定を変更しない。
- Phase の境界を守る。特に Phase 4 で Phase 6 の最終提出作業を実施しない。
