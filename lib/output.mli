type format = Plain | Json

val warning_to_string : Analysis.warning -> string
val string_of_time : ?timezone:Timezone.t -> Ptime.t -> string

val pp_next :
  ?timezone:Timezone.t ->
  Format.formatter ->
  format:format ->
  expr:string ->
  Ptime.t list ->
  unit

val pp_warnings :
  Format.formatter ->
  format:format ->
  expr:string ->
  Analysis.warning list ->
  unit

val pp_conflicts :
  ?timezone:Timezone.t ->
  Format.formatter ->
  format:format ->
  Analysis.conflict list ->
  unit

val pp_overlaps :
  ?timezone:Timezone.t ->
  Format.formatter ->
  format:format ->
  Analysis.overlap list ->
  unit

val pp_check :
  timezone:Timezone.t ->
  Format.formatter ->
  format:format ->
  Check.report ->
  unit
