#!/bin/bash
# Aurora/RDS Performance Insights からベンチ窓の SQL 別 DB Load (AAS) と wait event を取得し、
# markdown を stdout に出す。slow log より正確にボトルネック SQL を順位付けする。
# scripts/ecs/analyze.sh から呼ぶほか、単体でも実行できる。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/ecs/lib.sh
source "$SCRIPT_DIR/lib.sh"
ecs_load_env

START_EPOCH="${BENCH_START_EPOCH:-}"
END_EPOCH=""
PI_PERIOD="${PI_PERIOD:-60}"

usage() {
  cat <<'EOF'
Usage:
  scripts/ecs/pi.sh [--since-epoch <epoch>] [--end-epoch <epoch>]

Environment:
  BENCH_START_EPOCH  default window start (else now-10min)
  PI_PERIOD          Performance Insights period seconds (1/60/300/3600/86400), default: 60
  RDS_INSTANCE       DB instance id (DbiResourceId を解決するために使う)
  PI_IDENTIFIER      DbiResourceId を直接指定する場合に使う (RDS_INSTANCE をスキップ)

Requires IAM: pi:GetResourceMetrics, rds:DescribeDBInstances
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
if [ "$((END_EPOCH - START_EPOCH))" -lt "$PI_PERIOD" ]; then
  START_EPOCH="$((END_EPOCH - PI_PERIOD))"
fi

START_ISO="$(date -u -d "@$START_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"
END_ISO="$(date -u -d "@$END_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"

# PI の identifier は instance id ではなく DbiResourceId。
PI_ID="${PI_IDENTIFIER:-}"
if [ -z "$PI_ID" ] && [ -n "${RDS_INSTANCE:-}" ]; then
  PI_ID="$(ecs_aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE" \
    --query 'DBInstances[0].DbiResourceId' --output text 2>/dev/null || true)"
fi

if [ -z "$PI_ID" ] || [ "$PI_ID" = "None" ]; then
  echo "## Performance Insights"
  echo ""
  echo "> RDS_INSTANCE / PI_IDENTIFIER が未設定、または Performance Insights が無効。スキップ。"
  echo ""
  exit 0
fi

# group by された get-resource-metrics の MetricList を集約する。
# argv: <group>  group=db.sql_tokenized | db.wait_event
pi_render() {
  python3 -c '
import json, re, sys
group = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    print("TOTAL\tn/a")
    sys.exit()

def avg_points(points):
    vals = [p["Value"] for p in points if p.get("Value") is not None]
    return round(sum(vals) / len(vals), 3) if vals else None

def clean(label):
    label = re.sub(r"\s+", " ", str(label)).strip()
    if len(label) > 100:
        label = label[:100] + "..."
    return label.replace("|", "\\|")

total = "n/a"
rows = []
for entry in d.get("MetricList", []):
    key = entry.get("Key", {})
    dims = key.get("Dimensions")
    avg = avg_points(entry.get("DataPoints", []))
    if not dims:
        total = avg if avg is not None else "n/a"
        continue
    if avg is None:
        continue
    if group == "db.sql_tokenized":
        label = dims.get("db.sql_tokenized.statement", "(unknown)")
    else:
        label = dims.get("db.wait_event.name") or dims.get("db.wait_event.type") or "(unknown)"
    rows.append((avg, clean(label)))

rows.sort(key=lambda x: x[0], reverse=True)
print("TOTAL\t%s" % total)
for avg, label in rows[:10]:
    print("%s\t%s" % (avg, label))
' "$1"
}

pi_get() {
  local group="$1"
  ecs_aws pi get-resource-metrics --service-type RDS --identifier "$PI_ID" \
    --start-time "$START_ISO" --end-time "$END_ISO" --period-in-seconds "$PI_PERIOD" \
    --metric-queries "[{\"Metric\":\"db.load.avg\",\"GroupBy\":{\"Group\":\"$group\",\"Limit\":10}}]" \
    --output json 2>/dev/null || echo '{}'
}

sql_out="$(pi_get db.sql_tokenized | pi_render db.sql_tokenized)"
wait_out="$(pi_get db.wait_event | pi_render db.wait_event)"

sql_total="$(printf '%s\n' "$sql_out" | awk -F'\t' '$1=="TOTAL"{print $2; exit}')"

echo "## Performance Insights (DB Load)"
echo ""
echo "- **Window**: $START_ISO .. $END_ISO"
echo "- Identifier: \`$PI_ID\`"
echo ""
echo "### Top SQL by DB Load (AAS)"
echo "_Total DB Load (AAS) avg: ${sql_total:-n/a}_"
echo "| avg DB load (AAS) | SQL (tokenized) |"
echo "|---|---|"
if printf '%s\n' "$sql_out" | awk -F'\t' '$1!="TOTAL"{found=1} END{exit !found}'; then
  printf '%s\n' "$sql_out" | awk -F'\t' '$1!="TOTAL"{printf "| %s | %s |\n", $1, $2}'
else
  echo "| n/a | (PI 無効 or datapoint なし) |"
fi
echo ""
echo "### Top Wait Events"
echo "| avg DB load (AAS) | wait event |"
echo "|---|---|"
if printf '%s\n' "$wait_out" | awk -F'\t' '$1!="TOTAL"{found=1} END{exit !found}'; then
  printf '%s\n' "$wait_out" | awk -F'\t' '$1!="TOTAL"{printf "| %s | %s |\n", $1, $2}'
else
  echo "| n/a | (PI 無効 or datapoint なし) |"
fi
echo ""
echo "_AAS=Average Active Sessions。Performance Insights が有効で IAM に pi:GetResourceMetrics / rds:DescribeDBInstances が必要。_"
echo ""
