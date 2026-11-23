#!/bin/sh
# run-job NAME            run one cron now, exactly as its crontab line would
# run-job --force NAME    also run a disabled cron (its Cloud Scheduler job may still be live)
# run-job --list          list cron names and whether each is enabled
# The JSON result line is printed and also copied to the pod log ($CRON_LOG_TO, PID 1's
# stdout) so manual runs show up in Datadog next to scheduled ones.
# Exit codes: run-cron's (0 ok, 1 failed, 2 token missing, 3 already running),
# 4 disabled without --force, 5 unknown cron, 64 usage.
set -u
crontab=${CRON_CRONTAB:-/etc/cron-runner/crontab}
run_cron=${CRON_RUN_CRON:-/etc/cron-runner/run-cron}
log_to=${CRON_LOG_TO:-/proc/1/fd/1}

usage() { echo "usage: run-job [--force] NAME | run-job --list" >&2; exit 64; }

# Print "NAME STATE ARGS" for every run-cron line; ARGS is everything after "run-cron ".
lines() {
  awk '
    { state = "enabled"; line = $0
      if (line ~ /^# disabled: /) { state = "disabled"; sub(/^# disabled: /, "", line) }
      else if (line ~ /^#/) next
      i = index(line, "/run-cron ")
      if (i == 0) next
      args = substr(line, i + length("/run-cron "))
      split(args, f, " ")
      print f[1] "\t" state "\t" args }' "$crontab"
}

force=0
case "${1:-}" in
  --list) [ $# -eq 1 ] || usage; lines | awk -F '\t' '{ printf "%-45s %s\n", $1, $2 }'; exit 0 ;;
  --force) force=1; shift ;;
  ""|-*) usage ;;
esac
[ $# -eq 1 ] || usage
name=$1

match=$(lines | awk -F '\t' -v n="$name" '$1 == n')
if [ -z "$match" ]; then
  echo "run-job: no cron named '$name' (see run-job --list)" >&2
  exit 5
fi
state=$(printf '%s\n' "$match" | head -n 1 | cut -f 2)
args=$(printf '%s\n' "$match" | head -n 1 | cut -f 3-)

trigger=manual
if [ "$state" = "disabled" ]; then
  if [ "$force" -ne 1 ]; then
    echo "run-job: '$name' is disabled, so Cloud Scheduler may still run it; use --force to run it anyway" >&2
    exit 4
  fi
  trigger=manual-force-disabled
fi

# args comes from the chart-rendered crontab: NAME METHOD TIMEOUT TOKEN_KEY 'PATH'
eval "set -- $args"
out=$(CRON_TRIGGER=$trigger sh "$run_cron" "$@")
rc=$?
printf '%s\n' "$out"
{ printf '%s\n' "$out" >> "$log_to"; } 2>/dev/null || true
exit $rc
