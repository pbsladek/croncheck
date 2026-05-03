---
layout: default
render_with_liquid: false
---

# Timezones and DST

Times are UTC by default. Use `--tz` to analyze schedules in another timezone.

```sh
croncheck next "0 9 * * *" --tz America/New_York --count 5
croncheck next "0 9 * * *" --tz +02:00 --count 5
```

## Accepted timezone values

`--tz` accepts:

- `UTC`
- `Z`
- Fixed offsets such as `+02:00` or `-05:00`
- IANA names such as `America/New_York`

Crontab files can set schedule timezone with `CRON_TZ=America/New_York`.
Kubernetes CronJob YAML can set schedule timezone with `.spec.timeZone`.

## Wall-time semantics

Cron schedules are evaluated in local wall time for the selected scheduler
timezone. For example, `0 9 * * *` in `America/New_York` means 9:00 AM New York
time, even as the UTC offset changes across daylight saving time.

```sh
croncheck next "0 9 * * *" --tz America/New_York --from 2024-03-08 --count 5
```

## DST spring-forward gaps

If a local wall time does not exist because clocks jump forward, the fire time
is skipped.

Example: `0 2 * * *` in a zone where 2:00 AM is skipped on the spring-forward
date will not fire at that nonexistent local time.

```sh
croncheck next "0 2 * * *" --tz America/New_York --from 2024-03-09 --count 5
```

## DST fall-back folds

If a local wall time occurs twice because clocks fall back, `croncheck` reports
one fire for each real instant.

Example: `30 1 * * *` can fire twice on a fall-back date when 1:30 AM occurs
twice.

```sh
croncheck next "30 1 * * *" --tz America/New_York --from 2024-11-02 --count 5
```

## Host timezone database

IANA timezone support reads the host system zoneinfo database. Results can vary
if different systems have different timezone database versions.
