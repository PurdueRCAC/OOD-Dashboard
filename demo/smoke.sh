#!/usr/bin/env bash
# Smoke-test a running dashboard.
#
#   demo/smoke.sh                        # defaults to http://localhost:3000
#   demo/smoke.sh http://localhost:8080
#
# Checks every page and JSON endpoint the dashboard adds, so it is useful
# against a demo container and against a real deployment alike. JSON endpoints
# are additionally checked for a non-trivial body, because several of them
# return 200 with an empty list when their data source is missing -- which is
# the failure mode worth catching.
#
# Exits non-zero if anything fails.

set -uo pipefail

BASE="${1:-http://localhost:3000}"
TIMEOUT="${TIMEOUT:-30}"
pass=0
fail=0

green() { printf '\033[32m%s\033[0m' "$1"; }
red()   { printf '\033[31m%s\033[0m' "$1"; }

check() {
    local kind="$1" path="$2" label="$3"
    local body code
    body=$(curl -sS --max-time "$TIMEOUT" -w $'\n%{http_code}' "$BASE$path" 2>/dev/null) || {
        printf '  %s %-30s %s\n' "$(red FAIL)" "$path" "unreachable"
        fail=$((fail + 1)); return
    }
    code="${body##*$'\n'}"
    body="${body%$'\n'*}"

    if [ "$code" != "200" ]; then
        printf '  %s %-30s HTTP %s\n' "$(red FAIL)" "$path" "$code"
        fail=$((fail + 1)); return
    fi

    if [ "$kind" = "json" ]; then
        # An empty array is a 200, but it means the data source is not wired up.
        if [ ${#body} -lt 3 ] || [ "$body" = "[]" ] || [ "$body" = '"[]"' ]; then
            printf '  %s %-30s 200 but empty (%s)\n' "$(red FAIL)" "$path" "$label"
            fail=$((fail + 1)); return
        fi
    fi

    printf '  %s %-30s 200  %s\n' "$(green PASS)" "$path" "$label"
    pass=$((pass + 1))
}

echo "Testing $BASE"
echo
echo "Pages"
check html "/"                      "dashboard home"
check html "/cluster_status"        "cluster status"
check html "/myjobs"                "job history"
check html "/performance_metrics"   "performance metrics"
check html "/help/dashboard-guide"  "dashboard guide"
check html "/batch_connect/sessions" "interactive sessions"
check html "/apps/index"            "app index"

echo
echo "API endpoints"
check json "/api/partition_status"  "partitions"
check json "/api/cluster_status"    "nodes"
check json "/api/job_queue"         "queued/running jobs"
check json "/api/account_list"      "allocations"
check json "/api/balance_usage"     "balances"
check json "/api/disk_usage"        "filesystem quotas"
check json "/api/userdata"          "job history data"
check json "/api/news_feed"         "announcements"

echo
echo "Deep links"
# Pick a real job and node out of the running instance rather than guessing.
# Same reason as above: fetch into a variable first, so `head` closing the pipe
# early cannot turn into a spurious pipeline failure.
queue=$(curl -sS --max-time "$TIMEOUT" "$BASE/api/job_queue" 2>/dev/null)
nodes=$(curl -sS --max-time "$TIMEOUT" "$BASE/api/cluster_status" 2>/dev/null)
job=$(printf '%s' "$queue" | tr -d '\\' | grep -o '"jobid":"[0-9_]*"' | head -1 | cut -d'"' -f4)
node=$(printf '%s' "$nodes" | grep -o '"NodeName":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -n "$job" ]  && check html "/job/$job"    "job detail"  || echo "  (no job id found to test)"
[ -n "$node" ] && check html "/nodes/$node" "node detail" || echo "  (no node name found to test)"

echo
# Fetch first, match second. Piping curl into `grep -q` looks tidier but is a
# trap: grep exits at the first match, curl takes SIGPIPE, and `pipefail` then
# reports the whole pipeline as failed -- so a page that *does* contain the
# banner is reported as not having it.
home=$(curl -sS --max-time "$TIMEOUT" "$BASE/" 2>/dev/null)
case "$home" in
    *"every number on this page is invented"*)
        echo "Demo banner present -- this instance is serving invented data." ;;
    *)
        echo "No demo banner -- this instance is NOT in demo mode." ;;
esac

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ] || exit 1
