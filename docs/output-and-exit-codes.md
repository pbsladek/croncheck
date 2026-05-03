---
layout: default
render_with_liquid: false
---

# Output formats and exit codes

## Output formats

Most commands support:

```sh
--format plain
--format json
```

Plain output is intended for humans. JSON output is intended for automation and
CI.

## Time formats

Plain output supports:

```sh
--time-format rfc3339
--time-format human
```

RFC3339 is the default. Human time is useful for manual review:

```sh
croncheck next "0 9 * * *" --tz America/New_York --time-format human
```

JSON output always uses RFC3339. `--time-format human` is rejected with JSON so
machine consumers receive stable timestamps.

## Exit codes

- `0`: success, no findings.
- `1`: warnings, conflicts, overlaps, or policy violations found.
- `2`: cron parse error or input parse error.
- `3`: usage error.

For `check`, use `--fail-on` to choose which findings should produce exit code
`1`:

```sh
croncheck check --from-k8s cronjobs.yaml --fail-on policy,conflicts
croncheck check --from-k8s cronjobs.yaml --fail-on none
```

Accepted categories are `warnings`, `conflicts`, `overlaps`, and `policy`.
`all` is the default, and `none` reports findings without failing.

Policy files may also set a default:

```text
fail_on: policy,conflicts
```

The CLI flag takes precedence over the policy-file value.

## CI patterns

Fail a pull request when schedule findings exist:

```sh
croncheck check --from-k8s cronjobs.yaml --policy croncheck.policy
```

Introduce croncheck gradually by failing only on selected categories:

```sh
croncheck check --from-k8s cronjobs.yaml --policy croncheck.policy --fail-on policy
```

Produce machine-readable findings:

```sh
croncheck check --from-k8s cronjobs.yaml --policy croncheck.policy --format json
```

Use fixed start times in tests so output is deterministic:

```sh
croncheck check --from-k8s cronjobs.yaml --from 2024-01-01 --window 30d
```
