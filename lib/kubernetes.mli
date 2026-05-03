type error = { file : string; line : int option; message : string }
(** Kubernetes manifest parse error with best-effort line information. *)

val parse_lines :
  source_path:string -> string list -> (Job.t list, error list) result
(** Extract CronJob schedules and optional [spec.timeZone] values from a YAML
    stream. Embedded [TZ=] schedule prefixes are rejected at this boundary. *)

val parse_file : string -> (Job.t list, error list) result
