#!/bin/sh
# run-cron NAME METHOD TIMEOUT TOKEN_KEY PATH [SCHEDULE]
# One HTTP call to $CRON_TARGET$PATH, made like the Cloud Scheduler job it replaces.
# TOKEN_KEY "-" sends no token; otherwise its value is read from $CRON_TOKENS_FILE
# (KEY=value lines rendered by the Vault agent) and sent as the "token" header.
# Prints exactly one JSON line per run (supercronic passes it through to the pod log):
#   message, cron, schedule, trigger, method, url, http_code (int, 0 = no response),
#   http_class (2xx/3xx/4xx/5xx/none), result (success/failed/skipped/error),
#   duration_ms (int), curl_exit (int), level (info/warn/error).
# Exit 0 only on HTTP 2xx (the Cloud Scheduler success rule); no retries.
# Exit 2 if the token is missing, 3 if this cron is already running (a per-cron lock
# shared by scheduled runs and run-job, so a manual run never overlaps a scheduled one).
# CRON_TRIGGER (default "schedule") is copied into the line; run-job sets it to "manual".
set -u
name=$1 method=$2 timeout=$3 token_key=$4 path=$5 schedule=${6:-}
tokens_file=${CRON_TOKENS_FILE:-/vault/secrets/cron-tokens}
trigger=${CRON_TRIGGER:-schedule}
url="https://${CRON_HOST}${path}"

# emit RESULT LEVEL HTTP_CODE DURATION_MS CURL_EXIT MESSAGE
emit() {
  case "$3" in
    0) class=none ;;
    *) class="${3%??}xx" ;;
  esac
  printf '{"message":"%s","cron":"%s","schedule":"%s","trigger":"%s","method":"%s","url":"%s","http_code":%d,"http_class":"%s","result":"%s","duration_ms":%d,"curl_exit":%d,"level":"%s"}\n' \
    "$6" "$name" "$schedule" "$trigger" "$method" "$url" "$3" "$class" "$1" "$4" "$5" "$2"
}

if command -v flock >/dev/null 2>&1; then
  exec 9>"${CRON_LOCK_DIR:-/tmp}/run-cron-$name.lock"
  if ! flock -n 9; then
    emit skipped warn 0 0 0 "$name skipped: already running"
    exit 3
  fi
fi

set -- -sS -o /dev/null -w '%{http_code} %{time_total}' --max-time "$timeout" -X "$method" \
  -H "Host: $CRON_HOST" -H "X-Forwarded-Proto: https" -H "User-Agent: breadfast-cron-runner/$name"
if [ "$token_key" != "-" ]; then
  token=$(sed -n "s/^${token_key}=//p" "$tokens_file" 2>/dev/null | head -n 1)
  if [ -z "$token" ]; then
    emit error error 0 0 0 "$name error: token $token_key missing from $tokens_file"
    exit 2
  fi
  set -- "$@" -H "token: $token"
fi
[ "$method" = "GET" ] || set -- "$@" --data-binary ''

# curl's own error text is dropped so each run stays one log line; curl_exit carries the reason.
out=$(curl "$@" "$CRON_TARGET$path" 2>/dev/null)
rc=$?
# curl prints "000 <secs>" when there is no response.
code=$(printf '%s\n' "${out%% *}" | awk '{ print ($1 ~ /^[0-9]+$/) ? $1 + 0 : 0 }')
ms=$(printf '%s\n' "${out#* }" | awk '{ printf "%d", ($1 ~ /^[0-9.]+$/) ? $1 * 1000 + 0.5 : 0 }')
secs=$(awk -v m="$ms" 'BEGIN { printf "%.2f", m / 1000 }')

if [ "$rc" -eq 0 ] && [ "$code" -ge 200 ] && [ "$code" -le 299 ]; then
  emit success info "$code" "$ms" "$rc" "$name $method $code in ${secs}s"
  exit 0
fi
if [ "$code" -eq 0 ]; then
  emit failed error 0 "$ms" "$rc" "$name $method failed: no response (curl exit $rc) after ${secs}s"
else
  emit failed error "$code" "$ms" "$rc" "$name $method $code in ${secs}s"
fi
exit 1
