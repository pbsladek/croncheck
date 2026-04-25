Helper for normalizing ISO-8601 timestamps and human-format dates in output.

  $ normalize() {
  >   sed -E \
  >     -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[^ ,""]*/TIMESTAMP/g' \
  >     -e 's/[A-Z][a-z]+ [0-9]+ [A-Z][a-z]+ [0-9]+ at [0-9]+:[0-9]+ [AP]M/DATETIME/g'
  > }

next: JSON output includes expr, timezone, and times fields.

  $ croncheck next "*/15 * * * *" --count 3 --format json | grep -E '"expr"|"timezone"|"times"'
    "expr": "*/15 * * * *",
    "timezone": "UTC",
    "times": [

next: option order is flexible.

  $ croncheck next --format json --count 2 "@daily" | grep -E '"expr"|"timezone"'
    "expr": "@daily",
    "timezone": "UTC",

next: short -n flag works; plain format prints a header.

  $ croncheck next "@hourly" -n 1 | head -1
  Next fire times for @hourly (UTC):

next: fixed-offset timezone appears in header and output.

  $ croncheck next "0 9 * JAN MON-FRI" --count 2 --tz +02:00
  Next fire times for 0 9 * JAN MON-FRI (+02:00):
  2027-01-01T09:00:00+02:00
  2027-01-04T09:00:00+02:00

next: IANA timezone name appears in header.

  $ croncheck next "0 9 * * *" --count 1 --tz America/New_York --time-format human | head -1
  Next fire times for 0 9 * * * (America/New_York):

next: human format shows month name, weekday, and time.

  $ croncheck next "0 9 * JAN MON-FRI" --count 1 --tz +02:00 --time-format human
  Next fire times for 0 9 * JAN MON-FRI (+02:00):
  January 1 Fri 2027 at 9:00 AM +02:00

next: Quartz six-field expression is accepted.

  $ croncheck next "0 0 0 * * ?" --count 1 | head -1
  Next fire times for 0 0 0 * * ? (UTC):

next: Quartz seven-field expression with year field.

  $ croncheck next "0 0 0 ? JAN MON 2027" --count 1
  Next fire times for 0 0 0 ? JAN MON 2027 (UTC):
  2027-01-04T00:00:00Z

warn: rarely-firing expression exits 1 with warnings.

  $ croncheck warn "0 0 31 * *"
  Warnings for 0 0 31 * *:
  - rarely fires (7 times/year)
  - end-of-month trap; selected days do not occur every month
  [1]

warn: DOM+DOW conflict in JSON format.

  $ croncheck warn "0 0 15 * 1" --format json
  {
    "expr": "0 0 15 * 1",
    "warnings": [
      "day-of-month and day-of-week both restricted; POSIX cron uses OR semantics"
    ]
  }
  [1]

warn: clean expression exits 0.

  $ croncheck warn "0 0 * * *"
  No warnings for 0 0 * * *

warn: @reboot macro is unsupported; error to stderr, exits 2.

  $ croncheck warn "@reboot" 2>&1
  Error: invalid cron expression
    expression: @reboot
    reason: invalid syntax in macro field: "@reboot"
  [2]

Parse errors exit 2.

  $ croncheck warn "60 * * * *" 2>&1
  Error: invalid cron expression
    expression: 60 * * * *
    reason: minute value 60 is outside allowed range 0-59
  [2]

Unknown timezone exits 3.

  $ croncheck next "0 0 * * *" --tz No/Such_Zone 2>&1
  croncheck: option '--tz': unknown timezone; use UTC, Z, a fixed offset like
             +02:00, or an IANA name like America/New_York
  Usage: croncheck next [OPTION]… EXPR
  Try 'croncheck next --help' or 'croncheck --help' for more information.
  [3]

Typo in option name suggests the correct flag.

  $ croncheck next "0 0 * * *" --time-fortmat human 2>&1
  croncheck: unknown option '--time-fortmat', did you mean '--time-format'?
  Usage: croncheck next [OPTION]… EXPR
  Try 'croncheck next --help' or 'croncheck --help' for more information.
  [3]

Invalid duration unit.

  $ croncheck conflicts "*/5 * * * *" "*/3 * * * *" --window 10x 2>&1
  croncheck: option '--window': duration unit must be one of d, h, or m
  Usage: croncheck conflicts [OPTION]… EXPR EXPR
  Try 'croncheck conflicts --help' or 'croncheck --help' for more information.
  [3]

Oversized duration.

  $ croncheck conflicts "*/5 * * * *" "*/3 * * * *" --window 999999999999999d 2>&1
  croncheck: option '--window': duration is too large
  Usage: croncheck conflicts [OPTION]… EXPR EXPR
  Try 'croncheck conflicts --help' or 'croncheck --help' for more information.
  [3]

Negative count.

  $ croncheck next "0 0 * * *" --count=-1 2>&1
  croncheck: option '--count': count must be non-negative
  Usage: croncheck next [OPTION]… EXPR
  Try 'croncheck next --help' or 'croncheck --help' for more information.
  [3]

Negative threshold.

  $ croncheck conflicts "*/5 * * * *" "*/3 * * * *" --threshold=-1 2>&1
  croncheck: option '--threshold': threshold must be non-negative
  Usage: croncheck conflicts [OPTION]… EXPR EXPR
  Try 'croncheck conflicts --help' or 'croncheck --help' for more information.
  [3]

Negative overlap duration.

  $ croncheck overlaps "* * * * *" --duration=-1 2>&1
  croncheck: option '--duration': duration must be non-negative
  Usage: croncheck overlaps [OPTION]… EXPR
  Try 'croncheck overlaps --help' or 'croncheck --help' for more information.
  [3]

Invalid output format.

  $ croncheck warn "0 0 * * *" --format xml 2>&1
  croncheck: option '--format': expected output format 'plain' or 'json', got
             "xml"
  Usage: croncheck warn [--format=VAL] [--tz=VAL] [OPTION]… EXPR
  Try 'croncheck warn --help' or 'croncheck --help' for more information.
  [3]

Invalid time format.

  $ croncheck next "0 0 * * *" --time-format kitchen 2>&1
  croncheck: option '--time-format': expected time format 'rfc3339' or 'human',
             got "kitchen"
  Usage: croncheck next [OPTION]… EXPR
  Try 'croncheck next --help' or 'croncheck --help' for more information.
  [3]

JSON output rejects --time-format human.

  $ croncheck next "0 0 * * *" --format json --time-format human 2>&1
  Error: --time-format only applies to plain output
  Hint: Use --format plain with --time-format human, or omit --time-format for JSON.
  [3]

conflicts: found some; plain format shows timestamps.

  $ croncheck conflicts "*/5 * * * *" "*/3 * * * *" --window 60m --threshold 0 | normalize | head -3
  conflict at TIMESTAMP (delta 0s)
  conflict at TIMESTAMP (delta 0s)
  conflict at TIMESTAMP (delta 0s)
  $ croncheck conflicts "*/5 * * * *" "*/3 * * * *" --window 60m --threshold 0 > /dev/null
  [1]

conflicts: human format uses readable date and time.

  $ croncheck conflicts "*/5 * * * *" "*/3 * * * *" --window 60m --threshold 0 --time-format human | normalize | head -1
  conflict at DATETIME UTC (delta 0s)

conflicts: JSON output; option order is flexible.

  $ croncheck conflicts --format json --threshold 0 "*/5 * * * *" --window 60m "*/3 * * * *" | grep -E '"conflicts"|"delta"|"expr_' | head -4
    "conflicts": [
        "delta": 0,
        "expr_a": "*/5 * * * *",
        "expr_b": "*/3 * * * *"

overlaps: found some and exits 1.

  $ croncheck overlaps "* * * * *" --window 5m --duration 120 | normalize | head -3
  started TIMESTAMP, next fire TIMESTAMP, overrun by 60s
  started TIMESTAMP, next fire TIMESTAMP, overrun by 60s
  started TIMESTAMP, next fire TIMESTAMP, overrun by 60s
  $ croncheck overlaps "* * * * *" --window 5m --duration 120 > /dev/null
  [1]

overlaps: human format uses readable date and time.

  $ croncheck overlaps "* * * * *" --window 5m --duration 120 --time-format human | normalize | head -1
  started DATETIME UTC, next fire DATETIME UTC, overrun by 60s

overlaps: no findings; JSON output.

  $ croncheck overlaps "0 0 * * *" --duration 60 --window 60m --format json
  { "overlaps": [] }

check: stdin with two jobs, one warning.

  $ printf '%s\n' "0 0 * * *" "0 0 31 * *" | croncheck check --window 24h
  stdin:2: 0 0 31 * *
  - rarely fires (7 times/year)
  - end-of-month trap; selected days do not occur every month
  No conflicts found
  [1]

check: stdin parse error exits 2.

  $ printf '%s\n' "60 * * * *" | croncheck check 2>&1
  Error: failed to parse input
    - stdin:1: minute value 60 is outside allowed range 0-59
  [2]

check: missing crontab file exits 2.

  $ croncheck check --from-crontab no-such-file.txt 2>&1
  Error: failed to parse input
    - no-such-file.txt: no-such-file.txt: No such file or directory
  [2]

Create a system-format crontab file.

  $ cat > crontab.txt << 'EOF'
  > SHELL = /bin/sh
  > CRON_TZ=America/New_York
  > # comment
  > 0 0 31 * * root /usr/local/bin/monthly
  > EOF

check: system crontab warning includes job label and source line.

  $ croncheck check --from-crontab crontab.txt --system-crontab --window 24h
  crontab.txt:4 root: 0 0 31 * *
  - rarely fires (7 times/year)
  - end-of-month trap; selected days do not occur every month
  No conflicts found
  [1]

check: system crontab JSON preserves per-job timezone.

  $ croncheck check --from-crontab crontab.txt --system-crontab --window 24h --format json | grep -o '"timezone": "[^"]*"' | head -1
  "timezone": "America/New_York"

Create a Kubernetes CronJob manifest.

  $ cat > cronjob.yaml << 'EOF'
  > apiVersion: batch/v1
  > kind: CronJob
  > metadata:
  >   name: monthly31
  >   namespace: default
  > spec:
  >   schedule: "0 0 31 * *"
  >   timeZone: "America/New_York"
  > EOF

check: Kubernetes manifest produces warnings and correct JSON output.

  $ croncheck check --from-k8s cronjob.yaml --format json --window 24h
  {
    "jobs": [
      {
        "label": "cronjob.yaml:7 default/monthly31",
        "expr": "0 0 31 * *",
        "source": "cronjob.yaml",
        "line": 7,
        "command": null,
        "timezone": "America/New_York"
      }
    ],
    "warnings": [
      {
        "job": {
          "label": "cronjob.yaml:7 default/monthly31",
          "expr": "0 0 31 * *",
          "source": "cronjob.yaml",
          "line": 7,
          "command": null,
          "timezone": "America/New_York"
        },
        "warnings": [
          "rarely fires (7 times/year)",
          "end-of-month trap; selected days do not occur every month"
        ]
      }
    ],
    "conflicts": [],
    "overlaps": []
  }
  [1]

Create a Kubernetes manifest with an embedded TZ in the schedule.

  $ cat > bad-cronjob.yaml << 'EOF'
  > apiVersion: batch/v1
  > kind: CronJob
  > metadata:
  >   name: bad
  > spec:
  >   schedule: "TZ=America/New_York 0 9 * * *"
  > EOF

check: embedded TZ in Kubernetes schedule is rejected.

  $ croncheck check --from-k8s bad-cronjob.yaml 2>&1
  Error: failed to parse input
    - bad-cronjob.yaml:6: Kubernetes CronJob schedules must not contain TZ= or CRON_TZ=; use spec.timeZone instead
  [2]

check: conflicting input sources exits 3.

  $ croncheck check --from-crontab crontab.txt --from-k8s cronjob.yaml 2>&1
  Error: choose only one input source
  Hint: Use only one of --from-crontab or --from-k8s; omit both to read from stdin.
  [3]

explain: every-minute expression.

  $ croncheck explain "* * * * *"
  every minute

explain: common schedules.

  $ croncheck explain "0 0 * * *"
  at midnight

  $ croncheck explain "*/5 * * * *"
  every 5 minutes

  $ croncheck explain "0 9 * * 1-5"
  at 9:00 AM on Monday through Friday

  $ croncheck explain "0 0 1 * *"
  at midnight on 1st

explain: JSON format includes expr and description.

  $ croncheck explain "0 0 * * *" --format json
  { "expr": "0 0 * * *", "description": "at midnight" }

explain: invalid expression exits 2.

  $ croncheck explain "60 * * * *" 2>&1
  Error: invalid cron expression
    expression: 60 * * * *
    reason: minute value 60 is outside allowed range 0-59
  [2]

next: --from flag sets a fixed start time.

  $ croncheck next "0 0 * * *" --from 2024-01-01 --count 3
  Next fire times for 0 0 * * * (UTC):
  2024-01-02T00:00:00Z
  2024-01-03T00:00:00Z
  2024-01-04T00:00:00Z

next: --from accepts RFC3339 timestamp.

  $ croncheck next "0 0 * * *" --from 2024-06-15T12:00:00Z --count 2
  Next fire times for 0 0 * * * (UTC):
  2024-06-16T00:00:00Z
  2024-06-17T00:00:00Z

next: --gaps flag shows gap statistics.

  $ croncheck next "*/30 * * * *" --from 2024-01-01 --count 4 --gaps
  Next fire times for */30 * * * * (UTC):
  2024-01-01T00:30:00Z
  2024-01-01T01:00:00Z
  2024-01-01T01:30:00Z
  2024-01-01T02:00:00Z
  Gaps: min 30m, max 30m, avg 30m

next: --gaps in JSON output includes gaps object.

  $ croncheck next "*/30 * * * *" --from 2024-01-01 --count 3 --gaps --format json | grep -E '"gaps"|"min_s"|"max_s"|"avg_s"'
    "gaps": { "count": 2, "min_s": 1800, "max_s": 1800, "avg_s": 1800 }

conflicts: --from flag pins analysis window start.

  $ croncheck conflicts "*/5 * * * *" "*/15 * * * *" --from 2024-01-01 --window 15m | normalize
  conflict at TIMESTAMP (delta 0s)

overlaps: --from flag pins analysis window start.

  $ croncheck overlaps "* * * * *" --from 2024-01-01 --window 3m --duration 120 | normalize | head -2
  started TIMESTAMP, next fire TIMESTAMP, overrun by 60s
  started TIMESTAMP, next fire TIMESTAMP, overrun by 60s

next: --until bounds output to a window.

  $ croncheck next "0 * * * *" --from 2024-01-01 --until 2024-01-01T04:00:00Z
  Next fire times for 0 * * * * (UTC):
  2024-01-01T01:00:00Z
  2024-01-01T02:00:00Z
  2024-01-01T03:00:00Z
  2024-01-01T04:00:00Z

next: --until with --count uses whichever limit comes first.

  $ croncheck next "0 * * * *" --from 2024-01-01 --until 2024-01-01T06:00:00Z --count 3
  Next fire times for 0 * * * * (UTC):
  2024-01-01T01:00:00Z
  2024-01-01T02:00:00Z
  2024-01-01T03:00:00Z

next: --until with no fires in window prints empty list.

  $ croncheck next "0 0 1 1 *" --from 2024-02-01 --until 2024-03-01
  Next fire times for 0 0 1 1 * (UTC):

diff: identical schedules show = markers and exit 0.

  $ croncheck diff "*/5 * * * *" "*/5 * * * *" --from 2024-01-01 --window 15m
  = 2024-01-01T00:05:00Z
  = 2024-01-01T00:10:00Z
  = 2024-01-01T00:15:00Z

diff: no fires in window prints nothing and exits 0.

  $ croncheck diff "0 0 1 1 *" "0 0 1 2 *" --from 2024-03-01 --window 24h
  Schedules are identical

diff: different schedules mark left-only and right-only times.

  $ croncheck diff "0 9 * * *" "0 10 * * *" --from 2024-01-01 --window 48h
  < 2024-01-01T09:00:00Z
  > 2024-01-01T10:00:00Z
  < 2024-01-02T09:00:00Z
  > 2024-01-02T10:00:00Z
  [1]

diff: shared fire times are marked with =.

  $ croncheck diff "0 */6 * * *" "0 0 * * *" --from 2024-01-01 --window 24h
  < 2024-01-01T06:00:00Z
  < 2024-01-01T12:00:00Z
  < 2024-01-01T18:00:00Z
  = 2024-01-02T00:00:00Z
  [1]

diff: JSON output includes expr_a, expr_b, timezone, and diff fields.

  $ croncheck diff "0 9 * * *" "0 10 * * *" --from 2024-01-01 --window 24h --format json | grep -E '"expr_a"|"expr_b"|"timezone"|"diff"'
    "expr_a": "0 9 * * *",
    "expr_b": "0 10 * * *",
    "timezone": "UTC",
    "diff": [

warn: DST-observing timezone warns about 2 AM schedule.

  $ croncheck warn "0 2 * * *" --tz America/New_York
  Warnings for 0 2 * * *:
  - fires at 02:xx which falls in a common DST transition window; verify behavior with --tz
  [1]

warn: UTC timezone does not warn about 2 AM schedule.

  $ croncheck warn "0 2 * * *" --tz UTC
  No warnings for 0 2 * * *

warn: every-hour expression (Any hour field) does not trigger DST warning.

  $ croncheck warn "0 * * * *" --tz America/New_York
  No warnings for 0 * * * *

help: tool description is shown.

  $ croncheck --help | grep "Static analysis"
         croncheck - Static analysis for POSIX and basic Quartz cron
