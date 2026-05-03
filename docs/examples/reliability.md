---
layout: default
render_with_liquid: false
---

# Reliability checks

Use these examples to catch schedules that skip, collide, or overlap.

## Catch end-of-month traps

Schedules such as day 31 do not run every month.

```sh
croncheck warn "0 0 31 * *"
```

Use this for billing, reporting, and cleanup jobs that are intended to run
monthly but may silently skip months.

## Detect collisions between two jobs

If two expensive jobs should not start together, check their fire times.

```sh
croncheck conflicts "*/15 * * * *" "0 * * * *" \
  --from 2024-01-01 \
  --window 24h \
  --threshold 0
```

Increase `--threshold` to catch near misses, such as jobs starting within 5
minutes of each other.

```sh
croncheck conflicts "*/15 * * * *" "7 * * * *" \
  --window 24h \
  --threshold 300
```

## Check for self-overlap in long-running jobs

If a job can run longer than its schedule interval, it may overlap with itself.

```sh
croncheck overlaps "*/10 * * * *" \
  --window 24h \
  --duration 900
```

This example assumes a 15-minute duration for a job scheduled every 10 minutes.
