#!/bin/sh
# run-cron NAME METHOD TIMEOUT TOKEN_KEY PATH
# One HTTP call to $CRON_TARGET$PATH, made like the Cloud Scheduler job it replaces.
# TOKEN_KEY "-" sends no token; otherwise its value is read from $CRON_TOKENS_FILE
# (KEY=value lines rendered by the Vault agent) and sent as the "token" header.
# Exit 0 only on HTTP 2xx (the Cloud Scheduler success rule); no retries.
set -u
name=$1 method=$2 timeout=$3 token_key=$4 path=$5
tokens_file=${CRON_TOKENS_FILE:-/vault/secrets/cron-tokens}

set -- -sS -o /dev/null -w '%{http_code} %{time_total}' --max-time "$timeout" -X "$method" \
  -H "Host: $CRON_HOST" -H "X-Forwarded-Proto: https" -H "User-Agent: breadfast-cron-runner/$name"
if [ "$token_key" != "-" ]; then
  token=$(sed -n "s/^${token_key}=//p" "$tokens_file" 2>/dev/null | head -n 1)
  if [ -z "$token" ]; then
    printf '{"cron":"%s","error":"token %s missing from %s"}\n' "$name" "$token_key" "$tokens_file"
    exit 2
  fi
  set -- "$@" -H "token: $token"
fi
[ "$method" = "GET" ] || set -- "$@" --data-binary ''

out=$(curl "$@" "$CRON_TARGET$path")
rc=$?
code=${out%% *}
secs=${out#* }
printf '{"cron":"%s","method":"%s","path":"%s","http_code":"%s","seconds":"%s","curl_exit":%d}\n' \
  "$name" "$method" "$path" "$code" "$secs" "$rc"
case "$code" in
  2??) [ "$rc" -eq 0 ] && exit 0 ;;
esac
exit 1
