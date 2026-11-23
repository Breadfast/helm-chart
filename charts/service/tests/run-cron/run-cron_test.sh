#!/usr/bin/env bash
# Black-box tests for charts/service/files/cron-runner/run-cron.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../../files/cron-runner/run-cron.sh"
tmp=$(mktemp -d); log="$tmp/requests.log"; port=18080
python3 "$here/stub_server.py" "$port" "$log" & srv=$!
trap 'kill $srv 2>/dev/null; rm -rf "$tmp"' EXIT
for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$port/ok" && break; sleep 0.1; done
: > "$log"
printf "CRONS_TOKEN=s3cret\nHABDA_KEY=h4bda\n" > "$tmp/tokens"
export CRON_TARGET="http://127.0.0.1:$port" CRON_HOST="www.example.test" CRON_TOKENS_FILE="$tmp/tokens"
fails=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails+1)); fi; }
last() { tail -n 1 "$log" | python3 -c "import json,sys;print(json.load(sys.stdin)['$1'])"; }

out=$(sh "$script" job-a GET 10 CRONS_TOKEN '/ok/path?x=1&y=2'); rc=$?
check "2xx exits 0" '[ $rc -eq 0 ]'
check "query string kept" '[ "$(last path)" = "/ok/path?x=1&y=2" ]'
check "token header sent" '[ "$(last token)" = "s3cret" ]'
check "Host header sent" '[ "$(last host)" = "www.example.test" ]'
check "User-Agent names the cron" '[ "$(last ua)" = "breadfast-cron-runner/job-a" ]'
check "X-Forwarded-Proto https" '[ "$(last xfp)" = "https" ]'
check "JSON line has http_code 200" 'echo "$out" | python3 -c "import json,sys;assert json.load(sys.stdin)[\"http_code\"]==\"200\""'

sh "$script" job-b POST 10 - '/ok/post' >/dev/null; rc=$?
check "POST without token exits 0" '[ $rc -eq 0 ]'
check "method POST used" '[ "$(last method)" = "POST" ]'
check "no token header when key is -" '[ "$(last token)" = "None" ]'

sh "$script" job-c GET 10 - '/fail' >/dev/null; rc=$?
check "5xx exits 1" '[ $rc -eq 1 ]'

sh "$script" job-d GET 1 - '/slow' >/dev/null; rc=$?
check "timeout exits 1" '[ $rc -eq 1 ]'

n=$(wc -l < "$log")
sh "$script" job-e GET 10 LOCUSTOKEN '/ok' >/dev/null; rc=$?
check "missing token exits 2" '[ $rc -eq 2 ]'
check "missing token makes no request" '[ "$(wc -l < "$log")" -eq "$n" ]'

[ $fails -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
