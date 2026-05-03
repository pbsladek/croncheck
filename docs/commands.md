---
layout: default
render_with_liquid: false
---

# Command reference

## Global output options

Most commands support:

- `--format plain|json`: output format. Plain is the default.
- `--time-format rfc3339|human`: timestamp format for plain output.
- `--tz ZONE`: scheduler timezone. Defaults to `UTC`.
- `--from TIME`: analysis start time as RFC3339 or `YYYY-MM-DD`.

JSON output always uses RFC3339 timestamps.

## `explain`

Describe a cron expression in plain English.

```sh
croncheck explain "0 9 * * 1-5"
croncheck explain "0 9 * * 1-5" --format json
```

Use this command when reviewing a schedule in a pull request or translating
legacy crontab entries.

## `next`

Print upcoming fire times.

```sh
croncheck next "*/15 * * * *" --count 8
croncheck next "0 9 * * *" --tz America/New_York --time-format human
croncheck next "*/30 * * * *" --from 2024-01-01 --count 6 --gaps
croncheck next "0 * * * *" --from 2024-01-01 --until 2024-01-01T04:00:00Z
```

Important options:

- `--count`, `-n`: maximum number of fire times to print.
- `--until`: stop at a specific timestamp or date.
- `--gaps`: show min, max, and average gaps between returned fire times.

## `warn`

Report surprising schedule semantics.

```sh
croncheck warn "0 0 31 * *"
croncheck warn "0 2 * * *" --tz America/New_York
croncheck warn "0 0 15 * 1" --format json
```

Warnings include:

- Schedules that never fire.
- Rare schedules.
- POSIX day-of-month/day-of-week OR semantics.
- High-frequency schedules.
- End-of-month traps.
- Leap-year-only schedules.
- DST transition windows.

## `conflicts`

Find nearby fire times between two expressions.

```sh
croncheck conflicts "*/5 * * * *" "*/3 * * * *" --window 24h --threshold 0
croncheck conflicts "0 9 * * *" "0 9 * * 1-5" --from 2024-01-01 --window 30d
```

Important options:

- `--window`: analysis duration, such as `60m`, `24h`, or `30d`.
- `--threshold`: allowed distance in seconds between fire times.

## `overlaps`

Find self-overlaps for a job with an expected duration.

```sh
croncheck overlaps "* * * * *" --window 60m --duration 120s
croncheck overlaps "*/10 * * * *" --window 24h --duration 900s
```

Important options:

- `--duration`: assumed job duration, such as `30s`, `5m`, or `1h`.
- `--window`: analysis duration.

## `diff`

Compare two schedules over a window.

```sh
croncheck diff "0 9 * * *" "0 10 * * *" --window 7d
croncheck diff "0 */6 * * *" "0 0 * * *" --from 2024-01-01 --window 24h
```

Plain output markers:

- `<`: only the left expression fires.
- `>`: only the right expression fires.
- `=`: both expressions fire at that instant.

This is useful when changing production schedules.

## `check`

Analyze many schedules from stdin, crontab, or Kubernetes YAML.

```sh
printf '%s\n' "0 0 * * *" "0 0 31 * *" | croncheck check
croncheck check --from-crontab /etc/crontab --system-crontab
croncheck check --from-k8s cronjobs.yaml --format json
croncheck check --from-k8s cronjobs.yaml --policy croncheck.policy
croncheck check --from-k8s cronjobs.yaml --fail-on policy,conflicts
```

Important options:

- `--from-crontab PATH`: read a crontab file.
- `--system-crontab`: parse crontab as system format with a user column.
- `--from-k8s PATH`: read Kubernetes CronJob YAML.
- `--policy PATH`: enforce policy checks.
- `--fail-on CATEGORIES`: choose which findings exit `1`.
- `--duration`: optional job duration for overlap analysis.
- `--window`: analysis duration.

Only one input source can be selected. If no input source is selected, `check`
reads expressions from stdin.

`--fail-on` accepts a comma-separated list of `warnings`, `conflicts`,
`overlaps`, and `policy`. `all` is the default. `none` reports findings without
failing the command.

## `load`

Summarize schedule density across many jobs.

```sh
croncheck load --from-k8s cronjobs.yaml --window 7d --bucket 5m
printf '%s\n' "*/5 * * * *" "*/15 * * * *" | croncheck load --from 2024-01-01 --window 15m --bucket 1h
```

Important options:

- `--bucket`: bucket size, such as `5m`, `1h`, or `60m`.
- `--window`: analysis duration.
- `--from-crontab`, `--from-k8s`, or stdin.

Use `load` to identify thundering-herd risk, such as many CronJobs firing at
the same minute.

## `doctor`

Print runtime diagnostics for timezone and container setup.

```sh
croncheck doctor
croncheck doctor --tz America/New_York
croncheck doctor --tz UTC
```

The output includes:

- croncheck version marker.
- host OS type.
- zoneinfo search paths and whether they are present.
- parse status for the timezone probe.
- resolved zoneinfo file when the probe is an IANA timezone.

Use this when debugging timezone behavior in local environments or minimal
container images.
