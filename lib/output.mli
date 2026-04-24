type format = Plain | Json
type time_format = Rfc3339 | Human

val warning_to_string : Analysis.warning -> string

val string_of_time :
  ?timezone:Timezone.t -> ?time_format:time_format -> Ptime.t -> string

type gap_stats = { count : int; min_s : int; max_s : int; avg_s : int }

val compute_gaps : Ptime.t list -> gap_stats option
val format_gap_s : int -> string

val pp_next :
  ?timezone:Timezone.t ->
  ?time_format:time_format ->
  ?gaps:bool ->
  Format.formatter ->
  format:format ->
  expr:string ->
  Ptime.t list ->
  unit

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

val pp_check :
  timezone:Timezone.t ->
  ?time_format:time_format ->
  Format.formatter ->
  format:format ->
  Check.report ->
  unit
