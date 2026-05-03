---
layout: default
render_with_liquid: false
---

# Policy checks

Policy checks let teams enforce scheduling rules in CI.

Use `--policy` with `check`:

```sh
croncheck check --from-k8s cronjobs.yaml --policy croncheck.policy
```

Policy files are simple key-value files.

```text
forbid_every_minute: true
require_timezone: true
max_frequency_per_hour: 12
disallow_midnight_utc: true
```

Comments and blank lines are allowed.

## Rules

### `forbid_every_minute`

Reject schedules that fire every minute or more often.

```text
forbid_every_minute: true
```

This catches forms such as:

- `* * * * *`
- `*/1 * * * *`
- `0-59 * * * *`
- Quartz every-minute schedules.

### `require_timezone`

Require each job to specify an explicit timezone.

```text
require_timezone: true
```

This passes for:

- Crontab jobs following `CRON_TZ=...`
- Kubernetes CronJobs with `.spec.timeZone`

### `max_frequency_per_hour`

Reject schedules above a maximum hourly frequency.

```text
max_frequency_per_hour: 12
```

This is useful for preventing accidental high-frequency jobs in production.

### `disallow_midnight_utc`

Reject jobs that fire at midnight UTC within the analysis window.

```text
disallow_midnight_utc: true
```

This rule helps avoid common shared maintenance windows and top-of-day
thundering herds.

## Exit behavior

Policy violations are findings. `check --policy` exits `1` when any policy
violation is found.

Parse errors in the policy file exit `2`.

## JSON output

Policy violations are included in JSON output:

```sh
croncheck check --from-k8s cronjobs.yaml --policy croncheck.policy --format json
```

The JSON includes the job, rule name, and message for each violation.
