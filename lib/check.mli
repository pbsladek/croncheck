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

type policy_report = {
  report : report;
  policy_violations : Policy.violation list;
}

type finding_kind = Warnings | Conflicts | Overlaps | Policy

val load : source -> (Job.t list, string list) result

val analyze :
  timezone:Timezone.t ->
  from:Ptime.t ->
  until:Ptime.t ->
  threshold:int ->
  duration:int option ->
  Job.t list ->
  report

val analyze_with_policy :
  timezone:Timezone.t ->
  from:Ptime.t ->
  until:Ptime.t ->
  threshold:int ->
  duration:int option ->
  policy:Policy.t ->
  Job.t list ->
  policy_report

val has_findings : report -> bool
val has_policy_findings : policy_report -> bool
val has_findings_for : finding_kind list -> report -> bool
val has_policy_findings_for : finding_kind list -> policy_report -> bool
