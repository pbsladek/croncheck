type rule = private
  | ForbidEveryMinute
  | RequireTimezone
  | MaxFrequencyPerHour of int
  | DisallowMidnightUtc

type t = rule list

type config = { rules : t; fail_on : string list option }
(** Policy file contents. [rules] define violations. [fail_on] is optional
    execution policy for CI and may be overridden by the CLI. *)

type violation = private { job : Job.t; rule : rule; message : string }

val default : t
val forbid_every_minute : rule
val require_timezone : rule

val max_frequency_per_hour : int -> rule option
(** [max_frequency_per_hour n] is [None] for negative limits. *)

val disallow_midnight_utc : rule

val parse_file : string -> (t, string list) result
(** Parse only the rule portion of a policy file. *)

val parse_config_file : string -> (config, string list) result
(** Parse rules plus policy-file execution settings such as [fail_on]. *)

val evaluate :
  timezone:Timezone.t ->
  from:Ptime.t ->
  until:Ptime.t ->
  t ->
  Job.t list ->
  violation list
(** Evaluate rules inside the same bounded window used by schedule analysis.
    Rules that enumerate fire times must not inspect outside [[from], [until]].
*)

val rule_to_string : rule -> string
