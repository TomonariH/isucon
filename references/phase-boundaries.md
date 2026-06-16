# Phase Boundaries

Phase ごとの責務を混ぜないためのルール。

## Phase 2

- アプリ改善 loop。
- alp / slow query / `/isucon-analyze` で見える高・中インパクト候補を並列実装して評価する。
- pprof 導入やミドルウェア秘伝のタレ評価を主目的にしない。

## Phase 3

- pprof によるアプリ内部の CPU / heap / goroutine 分析。
- pprof 導入・取得・分析・アプリコード改善を扱う。
- ミドルウェア最終設定やログ停止をしない。

## Phase 4

- MySQL / nginx / memcached / Redis の設定を単体差分で評価する。
- 分析用ログを維持する。
- MySQL slow query log off、nginx access_log off、pprof 削除、分析用 override の整理などの最終提出作業は禁止。
- 最終スコア用に試す価値がある候補は `$TOOL_REPO/reports/infra-tuning.md` に記録し、実作業は Phase 6 に回す。

## Phase 5

- サーバー分割は `/goal` の長期 loop ではなく、まず `/isucon-multiserver` スキルで設計する。
- 最新 report、レギュレーション、利用可能サーバー、入口 URL、実行環境を確認してから分割案を出す。
- 複数案を反復 benchmark する場合だけ、`/isucon-multiserver` の出力を正本として別途 `/goal` を使う。

## Phase 6

- 最終提出用のサーバー整備。
- 新しい最適化を増やさない。
- 採用済み設定の固定、不要設定の無効化、再起動後の再現性確認だけを行う。
- pass していない構成を最終構成として扱わない。
