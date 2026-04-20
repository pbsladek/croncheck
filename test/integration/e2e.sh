#!/bin/sh

set -eu

DUNE=${DUNE:-dune}
EXE=${CRONCHECK_EXE:-_build/default/bin/main.exe}

"$DUNE" build >/dev/null

tmpdir=${TMPDIR:-/tmp}/croncheck-e2e.$$
mkdir -p "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

out=$tmpdir/stdout
err=$tmpdir/stderr

fail() {
  printf 'not ok - %s\n' "$1" >&2
  if [ -s "$out" ]; then
    printf '%s\n' 'stdout:' >&2
    sed -n '1,80p' "$out" >&2
  fi
  if [ -s "$err" ]; then
    printf '%s\n' 'stderr:' >&2
    sed -n '1,80p' "$err" >&2
  fi
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

run_cmd() {
  expected=$1
  name=$2
  shift 2

  set +e
  "$EXE" "$@" >"$out" 2>"$err"
  status=$?
  set -e

  if [ "$status" -ne "$expected" ]; then
    fail "$name: expected exit $expected, got $status"
  fi
}

run_cmd_stdin() {
  expected=$1
  name=$2
  input=$3
  shift 3

  set +e
  "$EXE" "$@" <"$input" >"$out" 2>"$err"
  status=$?
  set -e

  if [ "$status" -ne "$expected" ]; then
    fail "$name: expected exit $expected, got $status"
  fi
}

assert_stdout_contains() {
  needle=$1
  name=$2
  if ! grep -F -e "$needle" "$out" >/dev/null; then
    fail "$name: stdout did not contain $needle"
  fi
}

assert_stderr_contains() {
  needle=$1
  name=$2
  if ! grep -F -e "$needle" "$err" >/dev/null; then
    fail "$name: stderr did not contain $needle"
  fi
}

assert_stdout_matches() {
  pattern=$1
  name=$2
  if ! grep -E -e "$pattern" "$out" >/dev/null; then
    fail "$name: stdout did not match $pattern"
  fi
}

assert_stdout_empty() {
  name=$1
  if [ -s "$out" ]; then
    fail "$name: stdout should be empty"
  fi
}

assert_stderr_empty() {
  name=$1
  if [ -s "$err" ]; then
    fail "$name: stderr should be empty"
  fi
}

run_cmd 0 "next json" next "*/15 * * * *" --count 3 --format json
assert_stdout_contains '"expr": "*/15 * * * *"' "next json"
assert_stdout_contains '"times"' "next json"
assert_stderr_empty "next json"
pass "next json"

run_cmd 0 "next option order" next --format json --count 2 "@daily"
assert_stdout_contains '"expr": "@daily"' "next option order"
assert_stdout_contains '"times"' "next option order"
assert_stderr_empty "next option order"
pass "next option order"

run_cmd 0 "next short count option" next "@hourly" -n 1
assert_stdout_contains "Next fire times for @hourly" "next short count option"
assert_stdout_matches "T[0-9][0-9]:00:00Z" "next short count option"
assert_stderr_empty "next short count option"
pass "next short count option"

run_cmd 0 "next named fields and timezone" next "0 9 * JAN MON-FRI" --count 2 --tz +02:00
assert_stdout_contains "Next fire times for 0 9 * JAN MON-FRI (+02:00):" "next named fields and timezone"
assert_stdout_contains "+02:00" "next named fields and timezone"
assert_stderr_empty "next named fields and timezone"
pass "next named fields and timezone"

run_cmd 0 "next quartz six fields" next "0 0 0 * * ?" --count 1
assert_stdout_contains "Next fire times for 0 0 0 * * ? (UTC):" "next quartz six fields"
assert_stderr_empty "next quartz six fields"
pass "next quartz six fields"

run_cmd 0 "next quartz seven fields" next "0 0 0 ? JAN MON 2027" --count 1
assert_stdout_contains "2027-01" "next quartz seven fields"
assert_stderr_empty "next quartz seven fields"
pass "next quartz seven fields"

run_cmd 1 "warn finding" warn "0 0 31 * *"
assert_stdout_contains "end-of-month trap" "warn finding"
assert_stderr_empty "warn finding"
pass "warn finding"

run_cmd 1 "warn dom dow json" warn "0 0 15 * 1" --format json
assert_stdout_contains "POSIX cron uses OR semantics" "warn dom dow json"
assert_stdout_contains '"warnings"' "warn dom dow json"
assert_stderr_empty "warn dom dow json"
pass "warn dom dow json"

run_cmd 0 "warn clean" warn "0 0 * * *"
assert_stdout_contains "No warnings" "warn clean"
assert_stderr_empty "warn clean"
pass "warn clean"

run_cmd 2 "unsupported reboot macro" warn "@reboot"
assert_stdout_empty "unsupported reboot macro"
assert_stderr_contains "@reboot" "unsupported reboot macro"
pass "unsupported reboot macro"

run_cmd 2 "parse error" warn "60 * * * *"
assert_stdout_empty "parse error"
assert_stderr_contains "outside allowed range" "parse error"
pass "parse error"

run_cmd 3 "usage error" next "0 0 * * *" --tz America/Los_Angeles
assert_stdout_empty "usage error"
assert_stderr_contains "unsupported timezone" "usage error"
pass "usage error"

run_cmd 3 "invalid duration" conflicts "*/5 * * * *" "*/3 * * * *" --window 10x
assert_stdout_empty "invalid duration"
assert_stderr_contains "duration unit must be d, h, or m" "invalid duration"
pass "invalid duration"

run_cmd 3 "invalid format" warn "0 0 * * *" --format xml
assert_stdout_empty "invalid format"
assert_stderr_contains "unknown format" "invalid format"
pass "invalid format"

run_cmd 1 "conflicts" conflicts "*/5 * * * *" "*/3 * * * *" --window 60m --threshold 0
assert_stdout_contains "conflict at" "conflicts"
assert_stderr_empty "conflicts"
pass "conflicts"

run_cmd 1 "conflicts option order json" conflicts --format json --threshold 0 "*/5 * * * *" --window 60m "*/3 * * * *"
assert_stdout_contains '"conflicts"' "conflicts option order json"
assert_stdout_contains '"delta": 0' "conflicts option order json"
assert_stderr_empty "conflicts option order json"
pass "conflicts option order json"

run_cmd 1 "overlaps" overlaps "* * * * *" --window 5m --duration 120
assert_stdout_contains "overrun by" "overlaps"
assert_stderr_empty "overlaps"
pass "overlaps"

run_cmd 0 "overlaps no findings json" overlaps "0 0 * * *" --duration 60 --window 60m --format json
assert_stdout_contains '"overlaps": []' "overlaps no findings json"
assert_stderr_empty "overlaps no findings json"
pass "overlaps no findings json"

stdin_jobs=$tmpdir/jobs.txt
printf '%s\n' "0 0 * * *" "0 0 31 * *" >"$stdin_jobs"
run_cmd_stdin 1 "check stdin" "$stdin_jobs" check --window 24h
assert_stdout_contains "stdin:2" "check stdin"
assert_stdout_contains "end-of-month trap" "check stdin"
assert_stderr_empty "check stdin"
pass "check stdin"

bad_stdin_jobs=$tmpdir/bad-jobs.txt
printf '%s\n' "60 * * * *" >"$bad_stdin_jobs"
run_cmd_stdin 2 "check stdin parse error" "$bad_stdin_jobs" check
assert_stdout_empty "check stdin parse error"
assert_stderr_contains "stdin:1" "check stdin parse error"
assert_stderr_contains "outside allowed range" "check stdin parse error"
pass "check stdin parse error"

crontab=$tmpdir/crontab
{
  printf '%s\n' "SHELL = /bin/sh"
  printf '%s\n' "# comment"
  printf '%s\n' "0 0 31 * * root /usr/local/bin/monthly"
} >"$crontab"
run_cmd 1 "check system crontab" check --from-crontab "$crontab" --system-crontab --window 24h
assert_stdout_contains "$crontab:3" "check system crontab"
assert_stdout_contains "end-of-month trap" "check system crontab"
assert_stderr_empty "check system crontab"
pass "check system crontab"

k8s=$tmpdir/cronjob.yaml
{
  printf '%s\n' "apiVersion: batch/v1"
  printf '%s\n' "kind: CronJob"
  printf '%s\n' "metadata:"
  printf '%s\n' "  name: monthly31"
  printf '%s\n' "  namespace: default"
  printf '%s\n' "spec:"
  printf '%s\n' "  schedule: \"0 0 31 * *\""
} >"$k8s"
run_cmd 1 "check kubernetes json" check --from-k8s "$k8s" --format json --window 24h
assert_stdout_contains '"jobs"' "check kubernetes json"
assert_stdout_contains "default/monthly31" "check kubernetes json"
assert_stdout_contains "end-of-month trap" "check kubernetes json"
assert_stderr_empty "check kubernetes json"
pass "check kubernetes json"

run_cmd 3 "check conflicting input sources" check --from-crontab "$crontab" --from-k8s "$k8s"
assert_stdout_empty "check conflicting input sources"
assert_stderr_contains "choose only one input source" "check conflicting input sources"
pass "check conflicting input sources"

run_cmd 0 "help" --help
assert_stdout_contains "Static analysis" "help"
assert_stderr_empty "help"
pass "help"
