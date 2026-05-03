---
layout: default
render_with_liquid: false
---

# Analysis pipeline

The analysis pipeline takes normalized jobs and produces findings. It is shared
by single-purpose commands and the aggregate `check` command.

## Analysis layers

The core analysis module owns schedule-level behavior:

- warnings;
- pairwise conflicts;
- self-overlap;
- schedule diffs.

The check module owns source-level aggregation:

- loading input sources;
- applying warning checks to each job;
- comparing jobs for conflicts;
- optionally checking overlap;
- optionally applying policy rules.

This separation keeps cron semantics independent of CLI and file formats.

## Warning analysis

Warnings identify cron expressions that are valid but surprising:

- schedules that never fire;
- schedules that fire rarely;
- day-of-month/day-of-week ambiguity;
- high-frequency schedules;
- end-of-month traps;
- leap-year-only schedules;
- DST ambiguous hours.

Warnings should not change schedule behavior. They explain risks in schedules
that remain valid cron.

## Conflict analysis

Conflict analysis compares fire times from two schedules within a bounded
window. A conflict is reported when two fire times are separated by less than or
equal to the configured threshold.

The threshold is in seconds:

- `0` means exact same instant;
- larger values detect near misses.

Pairwise job comparison is expected for fleet checks. Any future scaling work
should preserve the same output contract while reducing repeated schedule
enumeration.

## Overlap analysis

Self-overlap checks compare consecutive fire times for one schedule. A schedule
overlaps when the configured duration exceeds the interval to the next fire.

Overlap findings record:

- `started_at`;
- `next_fire`;
- `overrun_by` in seconds.

The check command only runs overlap analysis when the user supplies a duration.

## Diff analysis

Diff compares two expressions over the same window and emits entries marked as:

- left only;
- right only;
- both.

This is intended for review workflows where a schedule change needs a concrete
list of behavioral differences.

## Exit behavior

The CLI treats findings as actionable by default. Aggregate checks exit
non-zero when warnings, conflicts, overlaps, or policy violations exist.

`--fail-on` can narrow that behavior to selected categories:

- warnings;
- conflicts;
- overlaps;
- policy.

The report still includes all findings. `--fail-on` only changes the exit code.
Parse and input errors use a separate error path from valid schedules with
findings.
