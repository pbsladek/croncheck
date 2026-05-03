type source =
  | Cli
  | Stdin
  | CrontabFile of string
  | KubernetesYaml of string
      (** Origin of a job. The value is diagnostic metadata; parsing has already
          normalized all sources to the same job shape. *)

type t = {
  id : string option;
  expr_raw : string;
  expr : Cron.expr;
  command : string option;
  source : source;
  line : int option;
  timezone : Timezone.t option;
}
(** A scheduled job after input loading. [expr_raw] is preserved for output,
    while [expr] is used for analysis. [timezone] is present only when the input
    source supplied a job-specific timezone. *)

val make :
  ?id:string ->
  ?command:string ->
  ?line:int ->
  ?timezone:Timezone.t ->
  source:source ->
  string ->
  (t, Cron.parse_error) result
(** Parse and construct a job from a raw expression. *)

val source_to_string : source -> string

val label : t -> string
(** Stable human label, preferring explicit ids and falling back to source line
    information or the raw expression. *)
