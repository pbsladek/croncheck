---
layout: default
render_with_liquid: false
---

# Input formats

`croncheck` can analyze a single expression, stdin lists, crontab files, and
Kubernetes CronJob manifests.

## Single expressions

Commands such as `explain`, `next`, `warn`, `conflicts`, `overlaps`, and `diff`
accept cron expressions directly on the command line.

```sh
croncheck explain "0 9 * * 1-5"
croncheck next "@daily" --count 3
```

Quote expressions in the shell so `*` is not expanded by your shell.

## Stdin

`check` and `load` read plain expressions from stdin when no file input option
is provided.

```sh
printf '%s\n' \
  "0 0 * * *" \
  "0 0 31 * *" \
  "*/5 * * * *" \
  | croncheck check
```

Blank lines and comments are ignored.

## Crontab files

Use `--from-crontab PATH`.

```sh
croncheck check --from-crontab ./crontab
```

System crontabs contain a user column between the schedule and command. Use
`--system-crontab` for that format.

```sh
croncheck check --from-crontab /etc/crontab --system-crontab
```

Crontab parsing supports:

- Environment assignments.
- Comments and blank lines.
- Standard user crontabs.
- System crontabs with a user column.
- `CRON_TZ=Zone/Name` for following jobs.

Example:

```crontab
SHELL=/bin/sh
CRON_TZ=America/New_York
0 9 * * 1-5 /usr/local/bin/report
0 0 31 * * /usr/local/bin/month-end
```

## Kubernetes CronJob YAML

Use `--from-k8s PATH`.

```sh
croncheck check --from-k8s cronjobs.yaml
croncheck load --from-k8s cronjobs.yaml --window 7d --bucket 5m
```

`croncheck` reads:

- `kind: CronJob`
- `metadata.name`
- `metadata.namespace`
- `spec.schedule`
- `spec.timeZone`

Example:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: billing-rollup
  namespace: finance
spec:
  schedule: "0 2 * * *"
  timeZone: "America/New_York"
```

Kubernetes CronJob schedules must not embed `TZ=` or `CRON_TZ=`. Use
`spec.timeZone` instead.
