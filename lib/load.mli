type job_count = private { job : Job.t; fires : int }

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

val analyze :
  timezone:Timezone.t ->
  from:Ptime.t ->
  until:Ptime.t ->
  bucket_seconds:int ->
  Job.t list ->
  report

val busiest : ?limit:int -> report -> bucket list
