---
layout: default
render_with_liquid: false
---

# Input loading

Input loading converts external sources into `Job.t` values. The rest of the
system should operate on jobs and should not need to know whether the input came
from stdin, a crontab file, or Kubernetes YAML.

## Job model

`Job.t` stores:

- optional stable id;
- raw cron expression;
- parsed `Cron.expr`;
- optional command;
- source metadata;
- optional line number;
- optional per-job timezone.

Source metadata is used in output and diagnostics. The parsed expression is kept
with the raw expression so analysis can be efficient while output remains useful
to humans.

## Source types

`Check.source` supports:

- `Stdin` for one expression per line;
- `Crontab` for user or system crontab files;
- `Kubernetes` for CronJob manifests.

`Check.load` normalizes all sources to `Job.t list` or a list of user-facing
input errors.

## Crontab parsing

Crontab parsing should preserve line-numbered diagnostics. It supports normal
environment assignments and treats `CRON_TZ=Zone/Name` as a schedule timezone
directive for following jobs.

Important distinction:

- `CRON_TZ` changes schedule interpretation.
- `TZ` is an environment assignment and does not change scheduler timezone.

System crontabs include a user column. The `system` flag controls that shape so
the parser does not guess.

## Kubernetes parsing

Kubernetes parsing extracts CronJob schedules and `.spec.timeZone` where
present. It rejects embedded `TZ=` and `CRON_TZ=` schedule prefixes because
Kubernetes does not support timezone directives inside `.spec.schedule`.

Kubernetes parser errors include the source file and best-effort line number.
The parser should keep YAML handling isolated from the rest of the analysis
pipeline.

## Timezone precedence

Timezone selection should follow this order:

1. Job-specific timezone from the input source.
2. CLI-selected timezone.
3. Default CLI timezone, currently UTC.

This lets a manifest or crontab carry its own intended timezone while still
allowing raw stdin expressions to be analyzed under a chosen timezone.

## Error boundary

Parsers return structured source-specific errors. `Check.load` converts them to
strings for the CLI boundary. Lower-level modules should avoid printing or
exiting directly.

