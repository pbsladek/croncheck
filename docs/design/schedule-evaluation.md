---
layout: default
render_with_liquid: false
---

# Schedule evaluation

Schedule evaluation converts parsed cron expressions into ordered UTC instants.
This is where cron's local-wall-time semantics meet `Ptime.t`.

## Core invariant

Cron expressions are evaluated in a selected scheduler timezone. The expression
itself is timezone-neutral unless it came from a source that supplied a timezone,
such as crontab `CRON_TZ` or Kubernetes `.spec.timeZone`.

The scheduler must return fire times that are:

- strictly ascending;
- deduplicated;
- bounded by the caller's `from` and `until` window when using bounded helpers;
- represented as `Ptime.t` instants.

## Compilation

`Schedule.compile` precomputes expanded field values and the selected timezone.
Callers that evaluate a schedule repeatedly should use the compiled API:

- `matches_compiled`
- `fire_times_compiled`
- `count_within`
- `next_n_compiled`
- `within_compiled`

The convenience wrappers compile once per call and are best for command-level
operations.

## Local candidate generation

The scheduler generates local date-time candidates, then maps each local
candidate through `Timezone.instants_of_local_date_time`.

That mapping can produce:

- zero instants for nonexistent local times during DST gaps;
- one instant for normal local times;
- two instants for repeated local times during DST folds.

This is the intended behavior. Cron is expressed in local wall time, so an
ambiguous local time should fire once for each real instant.

## DST behavior

DST gap behavior:

- If a local wall time does not exist, skip it.
- Example: `0 2 * * *` in `America/New_York` does not fire at nonexistent
  spring-forward `02:00` times.

DST fold behavior:

- If a local wall time occurs twice, fire for both real instants.
- Example: `30 1 * * *` in `America/New_York` can fire twice on fall-back day.

Fixed offsets and UTC have no gaps or folds.

## Matching vs enumeration

`matches` answers whether a specific instant is a fire time. Enumeration answers
what instants fire after a boundary. These must agree for normal instants, but
enumeration is the source of truth for DST folds because one local wall time can
map to multiple real instants.

## Safety expectations

Most command paths operate over bounded windows. Any new analysis that may scan
future fire times should use a window and an explicit limit where possible. This
prevents rare or impossible schedules from becoming unbounded searches.

