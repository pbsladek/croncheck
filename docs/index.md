---
layout: default
render_with_liquid: false
---

# croncheck documentation

`croncheck` is an offline CLI for static analysis of cron expressions and
scheduled jobs. It explains schedules, previews fire times, detects surprising
cron semantics, finds conflicts, checks long-running jobs for self-overlap,
summarizes fleet load, and enforces simple CI policies.

## Documentation

- [Installation](install.md)
- [Command reference](commands.md)
- [Input formats](input-formats.md)
- [Timezones and DST](timezones.md)
- [Policy checks](policies.md)
- [Output formats and exit codes](output-and-exit-codes.md)
- [Real-world examples](examples/index.md)
- [Design and planning](design/index.md)

## Quick start

Explain a schedule:

```sh
croncheck explain "0 9 * * 1-5"
```

Preview the next fire times:

```sh
croncheck next "*/15 * * * *" --count 8
```

Check several schedules from stdin:

```sh
printf '%s\n' "0 0 * * *" "0 0 31 * *" | croncheck check
```

Analyze Kubernetes CronJobs:

```sh
croncheck check --from-k8s cronjobs.yaml --format json
```

Run policy checks in CI:

```sh
croncheck check --from-k8s cronjobs.yaml --policy croncheck.policy
```

## Supported schedule syntax

`croncheck` supports:

- POSIX-style 5-field cron expressions.
- Numeric values, ranges, lists, and steps.
- Month and weekday names, such as `JAN` and `MON`.
- Sunday as `0` or `7`.
- Recurring macros: `@hourly`, `@daily`, `@weekly`, `@monthly`, and `@yearly`.
- Basic Quartz 6/7-field expressions with seconds, optional year, and `?`.

`@reboot` is rejected because it is not a recurring static schedule.

## Common workflow

1. Use `explain` to make a schedule readable.
2. Use `next --from ...` to preview exact future fire times.
3. Use `warn` to catch surprising semantics.
4. Use `check` for a full file, manifest, or stdin list.
5. Use `load` when many jobs could create thundering-herd risk.
6. Use `--policy` in CI to prevent risky schedule patterns from landing.
