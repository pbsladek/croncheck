type format = Plain | Json

type time_format =
  | Rfc3339
  | Human
      (** Output choices. JSON always uses RFC3339 timestamps; [Human] is a
          plain output presentation only. *)

val warning_to_string : Analysis.warning -> string

val string_of_time :
  ?timezone:Timezone.t -> ?time_format:time_format -> Ptime.t -> string
(** Render an instant using the offset active in [timezone] at that instant. *)

type gap_stats = { count : int; min_s : int; max_s : int; avg_s : int }

val compute_gaps : Ptime.t list -> gap_stats option
(** Compute intervals between consecutive sorted fire times. *)

val format_gap_s : int -> string
(** Format a duration in seconds for compact human output. *)

val pp_next :
  ?timezone:Timezone.t ->
  ?time_format:time_format ->
  ?gaps:bool ->
  Format.formatter ->
  format:format ->
  expr:string ->
  Ptime.t list ->
  unit
(** Render the [next] command. [gaps] augments the report without changing the
    returned fire-time list. *)

val pp_explain :
  Format.formatter -> format:format -> expr:string -> string -> unit

val pp_warnings :
  Format.formatter ->
  format:format ->
  expr:string ->
  Analysis.warning list ->
  unit

val pp_conflicts :
  ?timezone:Timezone.t ->
  ?time_format:time_format ->
  Format.formatter ->
  format:format ->
  Analysis.conflict list ->
  unit

val pp_overlaps :
  ?timezone:Timezone.t ->
  ?time_format:time_format ->
  Format.formatter ->
  format:format ->
  Analysis.overlap list ->
  unit

val pp_diff :
  ?timezone:Timezone.t ->
  ?time_format:time_format ->
  Format.formatter ->
  format:format ->
  expr_a:string ->
  expr_b:string ->
  Analysis.diff_entry list ->
  unit

val pp_load :
  ?time_format:time_format ->
  Format.formatter ->
  format:format ->
  Load.report ->
  unit

val pp_check :
  timezone:Timezone.t ->
  ?time_format:time_format ->
  Format.formatter ->
  format:format ->
  Check.report ->
  unit

val pp_check_with_policy :
  timezone:Timezone.t ->
  ?time_format:time_format ->
  Format.formatter ->
  format:format ->
  Check.policy_report ->
  unit
(** Render aggregate analysis plus policy findings. *)
