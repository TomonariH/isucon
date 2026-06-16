#!/bin/bash
# 競技 IAM role で analyze.sh が依存する AWS API に到達できるかを read-only で 1 回ずつ叩いて確認する。
# 結果を markdown table (| action | result | note |) で出す。result は OK / DENIED / OTHER。
# analyze.sh は失敗を || で握りつぶして n/a に落とすため、これがないと「権限拒否」と「データなし」を区別できない。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/ecs/lib.sh
source "$SCRIPT_DIR/lib.sh"
ecs_load_env

usage() {
  cat <<'EOF'
Usage:
  scripts/ecs/iam-check.sh

各 AWS API を read-only/cheap に 1 回だけ叩き、IAM 到達性を判定する。
出力: markdown table (| action | result | note |)。result は OK / DENIED / OTHER。

- OK     : rc==0。action は許可されている。
- DENIED : AccessDenied 系。analyze の該当セクションが n/a に落ちる。対応 SKIP_* を設定する。
- OTHER  : それ以外のエラー（resource-not-found 等）。多くは action 自体は許可されている。
- SKIP   : 必要な env var が未設定で probe できなかった行（informational）。

Requires: aws CLI。env var は scripts/env.sh から読む。
EOF
}

case "${1:-}" in
  -h|--help)
    usage; exit 0
    ;;
esac

ecs_require_cmd aws || exit 1

# probe <label> <note> <aws-subcommand...>
# rc==0 -> OK / stderr が AccessDenied 系 -> DENIED / それ以外 -> OTHER。
# 結果行を table に追記する。常に rc0 で返る（疎通確認は中断しない）。
probe() {
  local label="$1" note="$2"; shift 2
  local err rc result extra=""
  err="$(mktemp)"
  if ecs_aws "$@" >/dev/null 2>"$err"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    result="OK"
  elif grep -qE 'AccessDenied|not authorized|UnauthorizedOperation|AccessDeniedException' "$err"; then
    result="DENIED"
  else
    result="OTHER"
    # OTHER のときは原因の手掛かりを 1 行だけ note に足す。
    extra="$(head -n1 "$err" | tr -d '|' | cut -c1-80)"
  fi
  rm -f "$err"
  if [ -n "$extra" ]; then
    note="$note ($extra)"
  fi
  printf '| %s | %s | %s |\n' "$label" "$result" "$note"
}

# skip_row <label> <note>
# env var 不足などで probe できない行を informational に出す。
skip_row() {
  printf '| %s | SKIP | %s |\n' "$1" "$2"
}

NOW_EPOCH="$(date +%s)"
NOW_ISO="$(date -u -d "@$NOW_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"
AGO_ISO="$(date -u -d "@$((NOW_EPOCH - 300))" +%Y-%m-%dT%H:%M:%SZ)"

echo "# IAM Reach Check"
echo ""
echo "- **Date**: $NOW_ISO"
echo "- **Region**: ${AWS_REGION:-<aws-cli-default>}"
echo ""
echo "| action | result | note |"
echo "|---|---|---|"

# --- sts (常に) ---
probe "sts:GetCallerIdentity" "credential 疎通" sts get-caller-identity

# --- ecs ---
if [ -n "${ECS_CLUSTER:-}" ] && [ -n "${ECS_SERVICE:-}" ]; then
  probe "ecs:DescribeServices" "deploy/wait-stable に必要" \
    ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
else
  probe "ecs:ListClusters" "ECS_CLUSTER/ECS_SERVICE 未設定のため ListClusters で代替" \
    ecs list-clusters
fi

# --- ecr ---
probe "ecr:DescribeRepositories" "deploy.sh (image push)" \
  ecr describe-repositories --max-items 1

# --- elbv2 (ALB URL/dimension 解決) ---
probe "elbv2:DescribeLoadBalancers" "ALB URL/メトリクス dimension 解決" \
  elbv2 describe-load-balancers --page-size 1

# --- logs (group 一覧) ---
probe "logs:DescribeLogGroups" "discover.sh / log group 解決" \
  logs describe-log-groups --limit 1

# --- logs filter (analyze alp 入力) ---
NGINX_LOG_GROUP="$(ecs_log_group_for nginx)"
if [ -n "$NGINX_LOG_GROUP" ]; then
  probe "logs:FilterLogEvents" "analyze alp (nginx stdout 取得)。DENIED なら alp セクションが n/a" \
    logs filter-log-events --log-group-name "$NGINX_LOG_GROUP" --limit 1 \
    --start-time "$(((NOW_EPOCH - 60) * 1000))"
else
  skip_row "logs:FilterLogEvents" "ECS_NGINX_LOG_GROUP/ECS_LOG_GROUP 未設定。analyze alp の入力取得に必要"
fi

# --- cloudwatch (metrics.sh) ---
probe "cloudwatch:GetMetricStatistics" "metrics.sh。DENIED なら CloudWatch Metrics が n/a → SKIP_CW_METRICS=1" \
  cloudwatch get-metric-statistics --namespace AWS/ECS --metric-name CPUUtilization \
  --start-time "$AGO_ISO" --end-time "$NOW_ISO" --period 60 --statistics Average

# --- rds describe-db-instances ---
probe "rds:DescribeDBInstances" "discover/metrics/pi の前提" \
  rds describe-db-instances --max-items 1

# --- rds describe-db-parameters ---
if [ -n "${RDS_PARAM_GROUP:-}" ]; then
  probe "rds:DescribeDBParameters" "parameter group 確認 (Phase4)" \
    rds describe-db-parameters --db-parameter-group-name "$RDS_PARAM_GROUP" --max-items 1
else
  skip_row "rds:DescribeDBParameters" "RDS_PARAM_GROUP 未設定。Phase4 parameter group 確認に必要"
fi

# --- pi (pi.sh) ---
if [ -n "${RDS_INSTANCE:-}" ]; then
  PI_ID="$(ecs_aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE" \
    --query 'DBInstances[0].DbiResourceId' --output text 2>/dev/null || true)"
  if [ -n "$PI_ID" ] && [ "$PI_ID" != "None" ]; then
    probe "pi:GetResourceMetrics" "pi.sh。DENIED なら Performance Insights が n/a → SKIP_PI=1" \
      pi get-resource-metrics --service-type RDS --identifier "$PI_ID" \
      --start-time "$AGO_ISO" --end-time "$NOW_ISO" --period-in-seconds 60 \
      --metric-queries '[{"Metric":"db.load.avg"}]'
  else
    skip_row "pi:GetResourceMetrics" "DbiResourceId を解決できず (rds:DescribeDBInstances 不可 or PI 無効)。SKIP_PI=1 を検討"
  fi
else
  skip_row "pi:GetResourceMetrics" "RDS_INSTANCE 未設定。pi.sh に必要 (SKIP_PI=1 で skip)"
fi

# --- ec2 (discover.sh の到達性診断) ---
probe "ec2:DescribeSecurityGroups" "discover.sh (Aurora/pprof 到達性診断)" \
  ec2 describe-security-groups --max-items 1
probe "ec2:DescribeSubnets" "discover.sh (subnet/VPC 診断)" \
  ec2 describe-subnets --max-items 1

# --- sqs (bench queue 解決) ---
if [ -n "${BENCH_QUEUE_NAME:-${SQS_QUEUE_NAME:-}}" ]; then
  probe "sqs:GetQueueUrl" "bench-sqs.sh の queue URL 解決。NonExistentQueue は OTHER" \
    sqs get-queue-url --queue-name "${BENCH_QUEUE_NAME:-${SQS_QUEUE_NAME:-}}"
else
  skip_row "sqs:GetQueueUrl" "BENCH_QUEUE_NAME 未設定。bench-sqs.sh の queue URL 解決に必要"
fi

# --- 非 probe (informational) ---
skip_row "sqs:SendMessage" "ここでは probe しない (実送信になる)。bench-sqs.sh --dry-run で確認する"
skip_row "ecs:ExecuteCommand" "ここでは probe しない。Phase3 pprof (ECS Exec) で必要"

echo ""
echo "_DENIED の analyze セクションは対応する \`SKIP_*\` を設定し（DENIED metrics/PI/logs は \`n/a\` の理由になる＝「データなし」ではない）、結果を \`reports/survey.md\` に記録する。_"
