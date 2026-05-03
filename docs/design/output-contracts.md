---
layout: default
render_with_liquid: false
---

# Output contracts

Output formatting is the boundary between analysis data and users. The internal
modules should return typed values; only `Output` and the CLI should decide how
those values are rendered.

## Formats

The CLI supports:

- `plain` for human-readable terminal output;
- `json` for automation.

JSON output should be stable enough for CI and scripts. When adding fields,
prefer additive changes over renaming or removing existing fields.

## Time rendering

The internal representation for instants is `Ptime.t`. Output can render times
as:

- RFC3339, the default and the only JSON time format;
- human output for plain text.

`--time-format human` only applies to plain output. The CLI rejects JSON plus
human time formatting because machine-readable timestamps should remain
unambiguous.

## Timezone display

When a timezone is available, output should render instants using the effective
offset for that instant. This matters for IANA zones across DST boundaries.

JSON output should include the selected timezone name where the report shape has
room for it. Individual timestamps remain RFC3339 strings.

## Exit codes

The CLI distinguishes invalid execution from valid schedules with findings:

- `0` for successful commands with no findings;
- `1` for successful analysis that found warnings, conflicts, overlaps, or
  policy violations;
- `2` for input or parse errors;
- `3` for invalid CLI argument combinations.

New commands should follow this convention.

## Error printing

Low-level modules return errors. The CLI prints:

- short error heading;
- relevant expression, file, or line context when available;
- optional hint for recoverable usage mistakes.

This keeps library code reusable and prevents analysis modules from depending on
terminal behavior.

