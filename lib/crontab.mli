type error = { line : int option; message : string }
(** Crontab parse error. [line] is absent only for source-level failures such as
    file I/O. *)

val parse_lines :
  ?system:bool ->
  source_path:string ->
  string list ->
  (Job.t list, error list) result
(** Parse user crontab lines by default. [system] enables the user column used
    by [/etc/crontab]-style files. *)

val parse_file : ?system:bool -> string -> (Job.t list, error list) result
