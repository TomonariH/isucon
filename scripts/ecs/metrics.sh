#!/bin/bash
# ベンチ窓の CloudWatch メトリクス (Aurora / ALB / Fargate) を取得し markdown を stdout に出す。
# scripts/ecs/analyze.sh から呼ぶほか、単体でも実行できる。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/ecs/lib.sh
source "$SCRIPT_DIR/lib.sh"
ecs_load_env

START_EPOCH="${BENCH_START_EPOCH:-}"
END_EPOCH=""
PERIOD="${CW_PERIOD:-60}"

usage() {
  cat <<'EOF'
Usage:
  scripts/ecs/metrics.sh [--since-epoch <epoch>] [--end-epoch <epoch>]

Environment:
  BENCH_START_EPOCH  default window start (else now-10min)
  CW_PERIOD          CloudWatch period seconds, default: 60
  ECS_CLUSTER / ECS_SERVICE          AWS/ECS service metrics
  RDS_INSTANCE                       Aurora/RDS instance metrics
  RDS_CLUSTER                        Aurora cluster roll-up (AuroraReplicaLag)
  BACKEND_ALB_ARN / BACKEND_ALB_NAME AWS/ApplicationELB metrics (frontend も任意)

Requires IAM: cloudwatch:GetMetricStatistics, elasticloadbalancing:DescribeLoadBalancers
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --since-epoch)
      [ "$#" -ge 2 ] || { echo "[ecs] ERROR: --since-epoch requires a value" >&2; exit 2; }
      START_EPOCH="$2"; shift ;;
    --end-epoch)
      [ "$#" -ge 2 ] || { echo "[ecs] ERROR: --end-epoch requires a value" >&2; exit 2; }
      END_EPOCH="$2"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "[ecs] unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

ecs_require_cmd aws python3 || exit 1

[ -n "$START_EPOCH" ] || START_EPOCH="$(date -d '10 minutes ago' +%s)"
[ -n "$END_EPOCH" ] || END_EPOCH="$(date +%s)"
# 窓が短すぎると 1 つも datapoint が返らないことがあるため、最低 1 period 分は確保する。
if [ "$((END_EPOCH - START_EPOCH))" -lt "$PERIOD" ]; then
  START_EPOCH="$((END_EPOCH - PERIOD))"
fi

START_ISO="$(date -u -d "@$START_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"
END_ISO="$(date -u -d "@$END_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"

# get-metric-statistics の Datapoints を 1 つの代表値に集約する。
# key: Average|Maximum|Minimum|Sum|ext:<pXX>
cw_value() {
  python3 -c '
import json, sys
key = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    print("n/a"); sys.exit()
pts = d.get("Datapoints", [])
if not pts:
    print("n/a"); sys.exit()
if key.startswith("ext:"):
    p = key.split(":", 1)[1]
    vals = [x["ExtendedStatistics"][p] for x in pts if p in x.get("ExtendedStatistics", {})]
    print(round(max(vals), 3) if vals else "n/a"); sys.exit()
vals = [x[key] for x in pts if key in x]
if not vals:
    print("n/a"); sys.exit()
if key == "Sum":
    print(round(sum(vals), 3))
elif key == "Maximum":
    print(round(max(vals), 3))
elif key == "Minimum":
    print(round(min(vals), 3))
else:
    print(round(sum(vals) / len(vals), 3))
' "$1"
}

# metric_row <label> <namespace> <metric> <stat-key> <dim1> [dim2...]
# stat-key: Average|Maximum|Minimum|Sum|ext:<pXX>
metric_row() {
  local label="$1" ns="$2" metric="$3" statkey="$4"; shift 4
  local dims=("$@")
  local json value
  if [[ "$statkey" == ext:* ]]; then
    json="$(ecs_aws cloudwatch get-metric-statistics \
      --namespace "$ns" --metric-name "$metric" \
      --start-time "$START_ISO" --end-time "$END_ISO" --period "$PERIOD" \
      --extended-statistics "${statkey#ext:}" \
      --dimensions "${dims[@]}" --output json 2>/dev/null || echo '{}')"
  else
    json="$(ecs_aws cloudwatch get-metric-statistics \
      --namespace "$ns" --metric-name "$metric" \
      --start-time "$START_ISO" --end-time "$END_ISO" --period "$PERIOD" \
      --statistics "$statkey" \
      --dimensions "${dims[@]}" --output json 2>/dev/null || echo '{}')"
  fi
  value="$(printf '%s' "$json" | cw_value "$statkey")"
  printf '| %s | %s | %s |\n' "$label" "${statkey#ext:}" "$value"
}

echo "## CloudWatch Metrics"
echo ""
echo "- **Window**: $START_ISO .. $END_ISO (period ${PERIOD}s)"
echo ""

# ---- Aurora / RDS instance ----
echo "### Aurora / RDS"
echo ""
if [ -n "${RDS_INSTANCE:-}" ]; then
  echo "DBInstanceIdentifier=\`$RDS_INSTANCE\`"
  echo ""
  echo "| metric | stat | value |"
  echo "|---|---|---|"
  dim="Name=DBInstanceIdentifier,Value=$RDS_INSTANCE"
  metric_row "CPUUtilization (%)"          AWS/RDS CPUUtilization            Maximum "$dim"
  metric_row "CPUUtilization (%)"          AWS/RDS CPUUtilization            Average "$dim"
  metric_row "DatabaseConnections"         AWS/RDS DatabaseConnections       Maximum "$dim"
  metric_row "FreeableMemory (bytes)"      AWS/RDS FreeableMemory            Minimum "$dim"
  metric_row "BufferCacheHitRatio (%)"     AWS/RDS BufferCacheHitRatio       Average "$dim"
  metric_row "ReadLatency (s)"             AWS/RDS ReadLatency               Average "$dim"
  metric_row "WriteLatency (s)"            AWS/RDS WriteLatency              Average "$dim"
  metric_row "Deadlocks"                   AWS/RDS Deadlocks                 Sum     "$dim"
  metric_row "RowLockTime (ms)"            AWS/RDS RowLockTime               Average "$dim"
  # Aurora Serverless v2 のみ値が出る。provisioned では n/a。
  metric_row "ServerlessDatabaseCapacity (ACU)" AWS/RDS ServerlessDatabaseCapacity Maximum "$dim"
  echo ""
else
  echo "> RDS_INSTANCE が未設定。Aurora/RDS メトリクスをスキップ。"
  echo ""
fi

# ---- Aurora cluster roll-up (replica lag) ----
if [ -n "${RDS_CLUSTER:-}" ]; then
  echo "DBClusterIdentifier=\`$RDS_CLUSTER\` (cluster roll-up)"
  echo ""
  echo "| metric | stat | value |"
  echo "|---|---|---|"
  cdim="Name=DBClusterIdentifier,Value=$RDS_CLUSTER"
  metric_row "AuroraReplicaLag (ms)" AWS/RDS AuroraReplicaLag Maximum "$cdim"
  metric_row "AuroraReplicaLag (ms)" AWS/RDS AuroraReplicaLag Average "$cdim"
  echo ""
fi

# ---- ALB (backend / frontend) ----
emit_alb() {
  local kind="$1" dimval dim
  dimval="$(ecs_alb_dimension_for "$kind" 2>/dev/null || true)"
  echo "### ALB ($kind)"
  echo ""
  if [ -z "$dimval" ]; then
    echo "> ${kind} ALB ARN/Name が未解決。スキップ。"
    echo ""
    return
  fi
  echo "LoadBalancer=\`$dimval\`"
  echo ""
  echo "| metric | stat | value |"
  echo "|---|---|---|"
  dim="Name=LoadBalancer,Value=$dimval"
  metric_row "TargetResponseTime (s)"       AWS/ApplicationELB TargetResponseTime          Average "$dim"
  metric_row "TargetResponseTime (s)"       AWS/ApplicationELB TargetResponseTime          ext:p99 "$dim"
  metric_row "RequestCount"                 AWS/ApplicationELB RequestCount                 Sum     "$dim"
  metric_row "HTTPCode_Target_2XX"          AWS/ApplicationELB HTTPCode_Target_2XX_Count    Sum     "$dim"
  metric_row "HTTPCode_Target_4XX"          AWS/ApplicationELB HTTPCode_Target_4XX_Count    Sum     "$dim"
  metric_row "HTTPCode_Target_5XX"          AWS/ApplicationELB HTTPCode_Target_5XX_Count    Sum     "$dim"
  metric_row "HTTPCode_ELB_5XX"             AWS/ApplicationELB HTTPCode_ELB_5XX_Count       Sum     "$dim"
  metric_row "TargetConnectionErrorCount"   AWS/ApplicationELB TargetConnectionErrorCount   Sum     "$dim"
  metric_row "RejectedConnectionCount"      AWS/ApplicationELB RejectedConnectionCount      Sum     "$dim"
  metric_row "ActiveConnectionCount"        AWS/ApplicationELB ActiveConnectionCount        Maximum "$dim"
  echo ""
}

emit_alb backend
if [ -n "${FRONTEND_ALB_ARN:-}${FRONTEND_ALB_NAME:-}" ]; then
  emit_alb frontend
fi

# ---- ECS service (Fargate) ----
echo "### ECS service (Fargate)"
echo ""
if [ -n "${ECS_CLUSTER:-}" ] && [ -n "${ECS_SERVICE:-}" ]; then
  cluster_name="${ECS_CLUSTER##*/}"
  service_name="${ECS_SERVICE##*/}"
  echo "ClusterName=\`$cluster_name\` ServiceName=\`$service_name\`"
  echo ""
  echo "| metric | stat | value |"
  echo "|---|---|---|"
  metric_row "CPUUtilization (%)"    AWS/ECS CPUUtilization    Maximum "Name=ClusterName,Value=$cluster_name" "Name=ServiceName,Value=$service_name"
  metric_row "CPUUtilization (%)"    AWS/ECS CPUUtilization    Average "Name=ClusterName,Value=$cluster_name" "Name=ServiceName,Value=$service_name"
  metric_row "MemoryUtilization (%)" AWS/ECS MemoryUtilization Maximum "Name=ClusterName,Value=$cluster_name" "Name=ServiceName,Value=$service_name"
  metric_row "MemoryUtilization (%)" AWS/ECS MemoryUtilization Average "Name=ClusterName,Value=$cluster_name" "Name=ServiceName,Value=$service_name"
  echo ""
else
  echo "> ECS_CLUSTER / ECS_SERVICE が未設定。ECS メトリクスをスキップ。"
  echo ""
fi

echo "_n/a は当該メトリクス未対応・窓内 datapoint なし・dimension/権限不足のいずれか。CloudWatch メトリクスは publish 遅延（数分）があり、ベンチ直後は窓の最新分が過小/n/a になりうる。正確な値は数分後に \`BENCH_START_EPOCH=<epoch> bash scripts/ecs/analyze.sh\` で再取得する。_"
echo ""
