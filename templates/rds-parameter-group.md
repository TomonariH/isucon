# RDS パラメータグループ設定手順

RDS では `SET GLOBAL slow_query_log = 1` が使えないため、パラメータグループで設定する。

---

## 必要なパラメータ

| パラメータ | 設定値 | 説明 |
|-----------|-------|------|
| `slow_query_log` | `1` | スロークエリログを有効化 |
| `long_query_time` | `0` | 全クエリを記録（0 = すべて） |
| `log_output` | `TABLE` | `mysql.slow_log` テーブルに書き込む |

`log_output=TABLE` にすると `mysql.slow_log` テーブルにクエリが蓄積され、
`analyze-rds.sh` が直接 SELECT して pt-query-digest に流せる。

---

## AWS コンソールでの設定手順

1. AWS マネジメントコンソール → **RDS** → **パラメータグループ**
2. 使用中のパラメータグループを選択（またはカスタムグループを新規作成）
3. **パラメータの編集** をクリック
4. 検索で上記パラメータを探して値を設定
5. **変更を保存**
6. RDS インスタンスを再起動（static パラメータは再起動が必要）

> **注意**: デフォルトパラメータグループは直接編集できない。
> カスタムグループを作成して RDS インスタンスに紐付ける必要がある。

---

## AWS CLI での設定

```bash
# パラメータグループ名は環境変数で設定
export RDS_INSTANCE=isucon-db
export RDS_PARAM_GROUP=isucon-params

# setup-rds.sh --aws-cli を使う場合
bash scripts/setup-rds.sh --aws-cli

# 手動で設定する場合
aws rds modify-db-parameter-group \
  --db-parameter-group-name "$RDS_PARAM_GROUP" \
  --parameters \
    "ParameterName=slow_query_log,ParameterValue=1,ApplyMethod=immediate" \
    "ParameterName=long_query_time,ParameterValue=0,ApplyMethod=immediate" \
    "ParameterName=log_output,ParameterValue=TABLE,ApplyMethod=immediate"

# 変更後に再起動（static パラメータが含まれる場合）
aws rds reboot-db-instance --db-instance-identifier "$RDS_INSTANCE"
```

---

## 設定確認

```sql
-- RDS に接続して確認
SELECT @@slow_query_log, @@long_query_time, @@log_output;

-- スロークエリが蓄積されているか確認
SELECT COUNT(*) FROM mysql.slow_log;
SELECT * FROM mysql.slow_log ORDER BY start_time DESC LIMIT 5;
```

---

## スロークエリログの分析

設定完了後、ベンチマークを実行してから:

```bash
# analyze-rds.sh が mysql.slow_log から取得して pt-query-digest で分析する
DB_HOST=<rds-endpoint> DB_USER=isucon DB_PASS=isucon bash scripts/analyze-rds.sh
```

---

## Aurora の場合

Aurora MySQL でも同様にパラメータグループで設定できる。
ただし `log_output=TABLE` に加えて `general_log=0` を確認しておく（誤って有効化すると全クエリログが大量に溜まる）。
