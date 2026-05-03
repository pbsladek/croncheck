---
layout: default
render_with_liquid: false
---

# Fleet analysis

Use these examples to inspect many jobs at once.

## Analyze a crontab file

Check a user crontab:

```sh
croncheck check --from-crontab ./crontab --window 30d
```

Check a system crontab with the user column:

```sh
croncheck check --from-crontab /etc/crontab --system-crontab --window 30d
```

This reports warnings, conflicts, and optional overlap findings across all jobs
in the file.

## Find fleet load hotspots

Use `load` to identify many jobs firing in the same time bucket.

```sh
croncheck load --from-k8s cronjobs.yaml \
  --from 2024-01-01 \
  --window 7d \
  --bucket 5m
```

This helps find thundering-herd risk when many jobs fire at the top of the hour
or at midnight.
