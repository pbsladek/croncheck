---
layout: default
render_with_liquid: false
---

# Load analysis

Load analysis identifies time buckets where many jobs fire together. It is
designed to expose thundering-herd risk across a fleet.

## Report model

`Load.report` records:

- selected timezone;
- `from` and `until` bounds;
- bucket size in seconds;
- buckets with at least one fire.

Each bucket records:

- bucket start time;
- total fire count;
- per-job fire counts.

The per-job list lets output show which schedules contributed to a hotspot.

## Bucket semantics

Buckets are fixed-width intervals measured in seconds from the analysis start.
A fire belongs to the bucket containing its instant.

The analysis operates on UTC instants but formats bucket starts with the
selected output timezone. This keeps grouping stable while output remains
readable.

## Busiest buckets

`Load.busiest` sorts buckets by fire count and returns a limited list. The
default CLI behavior should present the highest-risk windows first instead of
dumping every bucket in a long analysis window.

Ties should remain deterministic by preserving a stable secondary ordering, such
as bucket start time.

## Scope

Load analysis answers "when do many things start?" It does not estimate runtime,
resource size, retries, or downstream contention. Those inputs are
service-specific and should be modeled separately if needed later.

## Future extension points

Potential future fields:

- job weight;
- expected duration;
- namespace or team grouping;
- top contributing sources;
- percentile summaries.

Any extension should preserve the current simple bucket report so existing JSON
consumers do not break unexpectedly.

