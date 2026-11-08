type source =
  | Stdin of string list
  | Crontab of { path : string; system : bool }
  | Kubernetes of string
      (** Input source normalized by [load]. Stdin accepts bare expressions and
          [label: expression] lines; file sources preserve source metadata on
          jobs. *)

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

type finding_kind =
  | Warnings
  | Conflicts
  | Overlaps
  | Policy
      (** Categories used only for exit-code selection. Reports are never
          filtered by this value. *)

val load : source -> (Job.t list, string list) result
(** Parse an input source into jobs. Errors are formatted with source context
    for the CLI boundary. *)

val analyze :
  timezone:Timezone.t ->
  from:Ptime.t ->
  until:Ptime.t ->
  threshold:int ->
  duration:int option ->
  Job.t list ->
  report
(** Analyze valid jobs over [[from], [until]]. [threshold] is a conflict
    distance in seconds. [duration] enables self-overlap checks when present. *)

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
(** Test whether a report contains findings in the selected categories. *)

val has_policy_findings_for : finding_kind list -> policy_report -> bool
