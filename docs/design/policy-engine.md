---
layout: default
render_with_liquid: false
---

# Policy engine

The policy engine provides a small, explicit rule set for CI. It is not a
general-purpose expression language.

## Goals

Policy checks should be:

- easy to read in code review;
- deterministic in CI;
- bounded by the same analysis window as schedule checks;
- implemented as typed rules rather than stringly typed predicates.

## Rule model

`Policy.rule` is a private variant. Callers create rules through constructors
and parse policy files through `Policy.parse_file`.

Current rules:

- `forbid_every_minute`
- `require_timezone`
- `max_frequency_per_hour`
- `disallow_midnight_utc`

`Policy.violation` is also private so callers cannot fabricate inconsistent
findings.

## Policy file format

Policy files use simple key-value lines:

```text
forbid_every_minute: true
require_timezone: true
max_frequency_per_hour: 12
disallow_midnight_utc: true
```

The format is deliberately small. Unsupported keys and invalid values should
produce clear parse errors rather than being ignored.

## Bounded evaluation

Rules that require schedule enumeration receive `from` and `until`. This keeps
CI behavior predictable and avoids unbounded scans.

Examples:

- `max_frequency_per_hour` can use the active analysis window.
- `disallow_midnight_utc` should only inspect midnight fires inside the window.

## Semantic checks

Policy checks should operate on cron semantics, not just raw strings.

For example, `forbid_every_minute` should catch equivalent forms such as:

- `* * * * *`
- `*/1 * * * *`
- `0-59 * * * *`

Raw expressions are still useful for messages, but rule decisions should prefer
parsed fields and schedule behavior.

## Relationship to warnings

Warnings are advisory findings for valid schedules. Policy violations are
organization-specific failures. The check command reports both when policy is
enabled and exits non-zero if either class of finding exists.

