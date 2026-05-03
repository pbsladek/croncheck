type rule = private
  | ForbidEveryMinute
  | RequireTimezone
  | MaxFrequencyPerHour of int
  | DisallowMidnightUtc

type t = rule list
type config = { rules : t; fail_on : string list option }
type violation = private { job : Job.t; rule : rule; message : string }

val default : t
val forbid_every_minute : rule
val require_timezone : rule
val max_frequency_per_hour : int -> rule option
val disallow_midnight_utc : rule
val parse_file : string -> (t, string list) result
val parse_config_file : string -> (config, string list) result

val evaluate :
  timezone:Timezone.t ->
  from:Ptime.t ->
  until:Ptime.t ->
  t ->
  Job.t list ->
  violation list

val rule_to_string : rule -> string
