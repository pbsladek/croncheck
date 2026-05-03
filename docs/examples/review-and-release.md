---
layout: default
render_with_liquid: false
---

# Review and release checks

Use these examples when a cron expression changes in a pull request or release.

## Explain a production schedule before review

Use `explain` when a cron expression appears in a pull request.

```sh
croncheck explain "0 9 * * 1-5"
```

Expected meaning:

```text
at 9:00 AM on Monday through Friday
```

This catches misunderstandings before reviewers need to mentally parse the
expression.

## Compare an old and new schedule before rollout

Use `diff` when changing a production schedule.

```sh
croncheck diff "0 9 * * *" "0 10 * * *" \
  --from 2024-01-01 \
  --window 7d
```

Plain output marks old-only fire times with `<`, new-only fire times with `>`,
and shared fire times with `=`.
