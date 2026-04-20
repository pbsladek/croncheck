type source =
  | Stdin of string list
  | Crontab of { path : string; system : bool }
  | Kubernetes of string

type report = {
  jobs : Job.t list;
  warnings : (Job.t * Analysis.warning list) list;
  conflicts : Analysis.conflict list;
  overlaps : Analysis.overlap list;
}

val load : source -> (Job.t list, string list) result

val analyze :
  timezone:Timezone.t ->
  from:Ptime.t ->
  until:Ptime.t ->
  threshold:int ->
  duration:int option ->
  Job.t list ->
  report

val has_findings : report -> bool
