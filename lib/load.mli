type job_count = private { job : Job.t; fires : int }
(** Number of fires contributed by one job to a load bucket. *)

type bucket = private {
  start : Ptime.t;
  fire_count : int;
  job_counts : job_count list;
}

type report = {
  timezone : Timezone.t;
  from : Ptime.t;
  until : Ptime.t;
  bucket_seconds : int;
  buckets : bucket list;
}
(** Bucketed fire counts over a bounded window. Buckets with no fires are
    omitted from [buckets]. *)

val analyze :
  timezone:Timezone.t ->
  from:Ptime.t ->
  until:Ptime.t ->
  bucket_seconds:int ->
  Job.t list ->
  report
(** Group job fire times into fixed-width buckets measured from [from]. *)

val busiest : ?limit:int -> report -> bucket list
(** Return buckets with the largest fire counts, keeping a deterministic order
    for ties. *)
