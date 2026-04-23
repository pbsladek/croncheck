# IANA Timezone Support Plan

## Goal

Add real timezone support while keeping cron semantics explicit and predictable.

Initial behavior supported only UTC and fixed offsets such as `+02:00`. IANA
timezone support is implemented by reading the host system zoneinfo database.

## Compatibility Targets

- POSIX 5-field cron expressions remain timezone-neutral. They are evaluated in
  the selected scheduler timezone.
- CLI `--tz` accepts `UTC`, `Z`, fixed offsets, and IANA names.
- Crontab parsing supports `CRON_TZ=Zone/Name` as a Cronie-style extension.
- Kubernetes parsing honors `.spec.timeZone`.
- Kubernetes schedule strings containing `TZ=` or `CRON_TZ=` remain rejected.
- JSON output includes the selected timezone name and RFC3339 timestamps with
  the effective offset at each instant.

## Dependency Plan

`ptime` should stay as the core timestamp representation.

No opam dependency is currently added. `Timezone` reads TZif files from system
zoneinfo directories such as `/usr/share/zoneinfo` and keeps the parser isolated
behind the `Timezone` module.

This means IANA results depend on the host or CI runner timezone database
version.

## Semantics

Cron schedules are defined in local wall time. The scheduler should generate
local candidate times and map them to instants.

DST gap behavior:

- If a local wall time does not exist, skip it.
- Example: `0 2 * * *` on a spring-forward day where `02:00` does not exist
  does not fire.

DST fold behavior:

- If a local wall time occurs twice, fire once for each real instant.
- Example: `30 1 * * *` on a fall-back day fires twice if `01:30` occurs twice.

Fixed offsets:

- Continue current behavior.
- No gaps or folds.

Display:

- RFC3339 output uses the offset active at that instant.
- Human output appends the timezone name for IANA zones and offset for fixed
  offsets.

## Implementation Phases

### Phase 1: Timezone Model

- Status: implemented.
- `Timezone.t` now supports:
  - `Utc`
  - `Fixed_offset of int`
  - `Iana of iana`
- `Timezone.parse` accepts valid IANA names backed by host TZif files.
- Added functions:
  - `to_string : t -> string`
  - `offset_seconds_at : t -> Ptime.t -> int`
  - `local_date_time : t -> Ptime.t -> Ptime.date * Ptime.time`
  - `instants_of_local_date_time : t -> Ptime.date * Ptime.time -> Ptime.t list`
- `offset_seconds` is retained for UTC/fixed offsets only. IANA callers use
  `offset_seconds_at`.

### Phase 2: Scheduler Refactor

- Status: implemented.
- Fixed-offset local conversions in `Schedule` were replaced with
  `Timezone.local_date_time`.
- Candidate local times are converted with
  `Timezone.instants_of_local_date_time`.
- POSIX minute schedules and Quartz second schedules both map local candidates
  to zero, one, or two instants.
- Generated fire times remain strictly ascending and deduplicated.

### Phase 3: Crontab `CRON_TZ`

- Status: implemented.
- Crontab parsing tracks `CRON_TZ=Zone/Name` and applies it to following jobs.
- `TZ=...` remains an environment assignment and does not change schedule
  timezone.
- Invalid `CRON_TZ` values produce line-numbered parse errors.

### Phase 4: Kubernetes `.spec.timeZone`

- Status: implemented.
- `.spec.timeZone` is read and validated with `Timezone.parse`.
- Schedules with embedded `TZ=` or `CRON_TZ=` are rejected with a
  Kubernetes-specific message.

### Phase 5: CLI and Output

- Status: implemented.
- `--tz` help documents:
  - `UTC`, `Z`, fixed offsets, or IANA names like `America/Los_Angeles`.
- JSON output keeps RFC3339 timestamps and includes the selected timezone.
- Human output includes the IANA name.

### Phase 6: Documentation

- Status: implemented.
- The README documents that POSIX cron itself does not put timezone names in
  expressions.
- Supported extensions are documented:
  - CLI `--tz`
  - crontab `CRON_TZ`
  - Kubernetes `.spec.timeZone`
- DST gap and fold behavior is documented.

## Test Plan

Unit tests:

- `Timezone.parse`
  - `UTC`
  - `Z`
  - `+02:00`
  - `America/New_York`
  - invalid names
- `Timezone.local_date_time`
  - winter offset
  - summer offset
  - historical transition if supported by dependency
- `Timezone.instants_of_local_date_time`
  - normal local time returns one instant
  - DST gap returns zero instants
  - DST fold returns two instants

Scheduler tests:

- `0 2 * * *` in `America/New_York` skips spring-forward `02:00`.
- `30 1 * * *` in `America/New_York` fires twice on fall-back day.
- `0 9 * * *` keeps local 09:00 across DST offset changes.
- Fixed-offset behavior remains unchanged.
- Quartz second-level schedules handle folds without duplicates.

Crontab tests:

- `CRON_TZ=America/New_York` applies to following jobs.
- A later `CRON_TZ=UTC` changes timezone for following jobs.
- Invalid `CRON_TZ` reports line-numbered parse error.
- `TZ=America/New_York` does not change schedule timezone unless explicitly
  documented otherwise.

Kubernetes tests:

- `.spec.timeZone: America/New_York` is applied.
- Invalid `.spec.timeZone` is rejected with file and line.
- Embedded `TZ=` or `CRON_TZ=` in `.spec.schedule` is rejected.

Integration tests:

- CLI `next --tz America/New_York` shows changing RFC3339 offsets across DST.
- CLI `--time-format human` includes the IANA name.
- `check --from-crontab` honors `CRON_TZ`.
- `check --from-k8s` honors `.spec.timeZone`.

## Release and Support Notes

- Treat this as a minor release because timezone behavior expands materially.
- Keep fixed-offset behavior backward compatible.
- Call out DST gap/fold semantics in release notes.
- Add CI tests that pin known DST transition dates so behavior stays stable.
- Results depend on the runner or host timezone database version.
- The TZif parser reads explicit transition tables and POSIX rule tails for
  future DST transitions.

## Open Questions

- Should a future release expose a diagnostic command that prints the active
  zoneinfo file and tzdata version when the host provides one?
- Should human output include both the zone name and numeric offset for IANA
  zones?
