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
# field NAME JSON -> "type:value" so tests can check JSON types (int vs str)
field() { python3 -c "import json,sys;v=json.loads(sys.argv[1]).get('$1');print(('int:' if type(v) is int else 'str:' if type(v) is str else 'other:')+str(v))" "$2"; }
last() { tail -n 1 "$log" | python3 -c "import json,sys;print(json.load(sys.stdin)['$1'])"; }

out=$(sh "$script" job-a GET 10 CRONS_TOKEN '/ok/path?x=1&y=2' '*/30 * * * *'); rc=$?
check "2xx exits 0" '[ $rc -eq 0 ]'
check "query string kept" '[ "$(last path)" = "/ok/path?x=1&y=2" ]'
check "token header sent" '[ "$(last token)" = "s3cret" ]'
check "Host header sent" '[ "$(last host)" = "www.example.test" ]'
check "User-Agent names the cron" '[ "$(last ua)" = "breadfast-cron-runner/job-a" ]'
check "X-Forwarded-Proto https" '[ "$(last xfp)" = "https" ]'
check "prints exactly one line" '[ "$(printf "%s\n" "$out" | wc -l)" -eq 1 ]'
check "http_code is the integer 200" '[ "$(field http_code "$out")" = "int:200" ]'
check "http_class 2xx" '[ "$(field http_class "$out")" = "str:2xx" ]'
check "result success, level info" '[ "$(field result "$out")" = "str:success" ] && [ "$(field level "$out")" = "str:info" ]'
check "schedule from the 6th argument" '[ "$(field schedule "$out")" = "str:*/30 * * * *" ]'
check "url is the public host plus path" '[ "$(field url "$out")" = "str:https://www.example.test/ok/path?x=1&y=2" ]'
check "cron, method and trigger fields" '[ "$(field cron "$out")" = "str:job-a" ] && [ "$(field method "$out")" = "str:GET" ] && [ "$(field trigger "$out")" = "str:schedule" ]'
check "duration_ms is an integer" 'field duration_ms "$out" | grep -q "^int:"'
check "message names cron, method and code" 'field message "$out" | grep -q "^str:job-a GET 200 in "'

sh "$script" job-b POST 10 - '/ok/post' >/dev/null; rc=$?
check "POST without token exits 0" '[ $rc -eq 0 ]'
check "method POST used" '[ "$(last method)" = "POST" ]'
check "no token header when key is -" '[ "$(last token)" = "None" ]'

out=$(sh "$script" job-c GET 10 - '/fail'); rc=$?
check "5xx exits 1" '[ $rc -eq 1 ]'
check "5xx: http_code 500, class 5xx, result failed, level error" '[ "$(field http_code "$out")" = "int:500" ] && [ "$(field http_class "$out")" = "str:5xx" ] && [ "$(field result "$out")" = "str:failed" ] && [ "$(field level "$out")" = "str:error" ]'
check "no schedule argument gives an empty schedule" '[ "$(field schedule "$out")" = "str:" ]'

out=$(sh "$script" job-d GET 1 - '/slow' 2>&1); rc=$?
check "timeout exits 1" '[ $rc -eq 1 ]'
check "timeout prints one line (curl error text dropped)" '[ "$(printf "%s\n" "$out" | wc -l)" -eq 1 ]'
check "timeout: http_code 0, class none, curl_exit 28" '[ "$(field http_code "$out")" = "int:0" ] && [ "$(field http_class "$out")" = "str:none" ] && [ "$(field curl_exit "$out")" = "int:28" ]'

n=$(wc -l < "$log")
out=$(sh "$script" job-e GET 10 LOCUSTOKEN '/ok'); rc=$?
check "missing token exits 2" '[ $rc -eq 2 ]'
check "missing token: result error, level error, http_code 0" '[ "$(field result "$out")" = "str:error" ] && [ "$(field level "$out")" = "str:error" ] && [ "$(field http_code "$out")" = "int:0" ]'
check "missing token makes no request" '[ "$(wc -l < "$log")" -eq "$n" ]'

[ $fails -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
