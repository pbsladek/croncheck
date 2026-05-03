---
layout: default
render_with_liquid: false
---

# Cron expression semantics

This document records the behavior `croncheck` treats as part of the core cron
spec. User documentation explains accepted syntax; this design note explains the
internal model and the edge cases that should remain stable.

## Expression model

`Cron.expr` has two top-level variants:

- `Posix` for 5-field expressions: minute, hour, day of month, month, day of
  week.
- `Quartz` for 6/7-field expressions: second, minute, hour, day of month,
  month, day of week, and optional year.

Field values are represented as a small AST:

- `Any`
- `Value`
- `Range`
- `Step`
- `List`

Quartz day-of-month and day-of-week fields use `day_field` so `?` can be
represented as `No_specific` instead of being confused with `*`.

## Parsing boundaries

Parsing is intentionally syntactic and range-aware. It validates the shape of an
expression and each field's allowed numeric bounds, but it does not decide
whether the schedule is operationally useful. For example, impossible or rare
calendar combinations are parsed first and reported later by analysis warnings.

Recurring macros are expanded before normal parsing. `@reboot` remains rejected
because it is event based, not a static recurring schedule.

## Day-of-month and day-of-week

POSIX cron has historically surprising semantics when both day-of-month and
day-of-week are specific. `croncheck` preserves those semantics in scheduling
and reports `DomDowAmbiguity` as an analysis warning instead of changing the
meaning.

Quartz uses `?` to mark one of those fields as intentionally unspecified. The
parser keeps this distinction so analysis and explanation can avoid treating
`?` as a normal wildcard.

## Expansion invariants

`Cron.expand` and `Cron.day_field_values` should return sorted, deduplicated
integer values within the requested range. This keeps downstream scheduling
logic deterministic and avoids duplicate fire times from list or step aliases.

Important examples:

- `*` expands to every value in the field range.
- `*/1` is semantically equivalent to `*`.
- `0-59`, `*/1`, and a complete list of minute values should be treated as
  every-minute schedules by policy checks.
- Sunday can be expressed as either `0` or `7` for POSIX compatibility.

## Error reporting

Parse errors are intentionally structured:

- `InvalidFieldCount`
- `FieldOutOfRange`
- `InvalidSyntax`

CLI and file parsers convert these to human-readable messages at the boundary.
The cron parser should not know whether input came from a CLI argument, stdin,
crontab, or Kubernetes YAML.

