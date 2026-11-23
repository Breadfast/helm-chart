#!/usr/bin/env bash
# Black-box tests for charts/service/files/cron-runner/run-job.sh (and the per-job lock in run-cron.sh)
set -u
here=$(cd "$(dirname "$0")" && pwd)
files="$here/../../files/cron-runner"
tmp=$(mktemp -d); log="$tmp/requests.log"; port=18081
python3 "$here/stub_server.py" "$port" "$log" & srv=$!
trap 'kill $srv 2>/dev/null; wait 2>/dev/null; rm -rf "$tmp"' EXIT
for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$port/ok" && break; sleep 0.1; done
: > "$log"
printf "CRONS_TOKEN=s3cret\n" > "$tmp/tokens"
# Same shape the chart renders: an enabled line, a disabled line, a slow line.
cat > "$tmp/crontab" <<'EOF'
# Rendered by the service chart from cronRunner.crons. Schedules are UTC.
0 */8 * * * /etc/cron-runner/run-cron job-on GET 180 CRONS_TOKEN '/ok/on?a=1&b=2'
# disabled: * * * * * /etc/cron-runner/run-cron job-off POST 30 - '/ok/off'
*/5 * * * * /etc/cron-runner/run-cron job-slow GET 10 - '/slow'
*/5 * * * * /etc/cron-runner/run-cron job-on-extra GET 10 - '/ok/extra'
EOF
export CRON_TARGET="http://127.0.0.1:$port" CRON_HOST="www.example.test" CRON_TOKENS_FILE="$tmp/tokens" \
  CRON_CRONTAB="$tmp/crontab" CRON_RUN_CRON="$files/run-cron.sh" CRON_LOG_TO="$tmp/podlog" CRON_LOCK_DIR="$tmp"
: > "$tmp/podlog"
runjob() { sh "$files/run-job.sh" "$@"; }
fails=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails+1)); fi; }
last() { tail -n 1 "$log" | python3 -c "import json,sys;print(json.load(sys.stdin)['$1'])"; }
field() { python3 -c "import json,sys;print(json.loads(sys.argv[1]).get('$1'))" "$2"; }

out=$(runjob job-on); rc=$?
check "enabled job exits 0" '[ $rc -eq 0 ]'
check "runs the crontab line's path with its query string" '[ "$(last path)" = "/ok/on?a=1&b=2" ]'
check "uses the crontab line's token" '[ "$(last token)" = "s3cret" ]'
check "uses the crontab line's method" '[ "$(last method)" = "GET" ]'
check "output is marked trigger manual" '[ "$(field trigger "$out")" = "manual" ]'
check "same line copied to the pod log" '[ "$(tail -n 1 "$tmp/podlog")" = "$out" ]'

n=$(wc -l < "$log")
out=$(runjob job-on-e 2>&1); rc=$?
check "name must match exactly (prefix of another job is unknown)" '[ $rc -eq 5 ]'
check "unknown job makes no request" '[ "$(wc -l < "$log")" -eq "$n" ]'

out=$(runjob job-off 2>&1); rc=$?
check "disabled job refused without --force" '[ $rc -eq 4 ]'
check "refusal says to use --force" 'echo "$out" | grep -q -- "--force"'
check "refused disabled job makes no request" '[ "$(wc -l < "$log")" -eq "$n" ]'

out=$(runjob --force job-off); rc=$?
check "disabled job runs with --force" '[ $rc -eq 0 ]'
check "forced run uses the disabled line's method" '[ "$(last method)" = "POST" ]'
check "forced run of a disabled job is marked" '[ "$(field trigger "$out")" = "manual-force-disabled" ]'

list=$(runjob --list); rc=$?
check "--list exits 0" '[ $rc -eq 0 ]'
check "--list shows enabled job" 'echo "$list" | grep -Eq "^job-on[[:space:]]+enabled"'
check "--list shows disabled job" 'echo "$list" | grep -Eq "^job-off[[:space:]]+disabled"'

runjob job-slow >/dev/null & bg=$!
sleep 0.5
n=$(wc -l < "$log")
out=$(runjob job-slow 2>&1); rc=$?
check "second run of a running job exits 3" '[ $rc -eq 3 ]'
check "second run says already running" 'echo "$out" | grep -q "already running"'
check "second run makes no request" '[ "$(wc -l < "$log")" -eq "$n" ]'
wait $bg; bgrc=$?
check "first run still finishes (timeout path, exit 1)" '[ $bgrc -eq 0 ] || [ $bgrc -eq 1 ]'

out=$(sh "$files/run-cron.sh" job-sched GET 10 - '/ok/sched'); rc=$?
check "scheduled run (no CRON_TRIGGER) is marked trigger schedule" '[ "$(field trigger "$out")" = "schedule" ]'

out=$(runjob 2>&1); rc=$?
check "no arguments prints usage and exits 64" '[ $rc -eq 64 ] && echo "$out" | grep -q usage'

[ $fails -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
