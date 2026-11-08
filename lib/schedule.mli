type compiled
(** Expanded schedule ready for repeated matching or enumeration. Compilation
    fixes the timezone and precomputes field membership. *)

val compile : ?timezone:Timezone.t -> Cron.expr -> compiled

val matches_compiled : compiled -> Ptime.t -> bool
(** [matches_compiled c t] tests [t] against the local wall time selected by
    [c]'s timezone. *)

val fire_times_compiled : compiled -> from:Ptime.t -> Ptime.t Seq.t
(** Infinite lazy sequence of fire instants strictly after [from], unless the
    schedule is impossible or bounded by a Quartz year field. *)

val count_within :
  ?limit:int -> compiled -> from:Ptime.t -> until:Ptime.t -> int
(** Count fires in [[from], [until]], stopping early at [limit] when supplied.
*)

val next_n_compiled : compiled -> from:Ptime.t -> int -> Ptime.t list

val within_compiled : compiled -> from:Ptime.t -> until:Ptime.t -> Ptime.t list
(** Enumerate fires in [[from], [until]]. Returned instants are ascending and
    deduplicated. *)

val fire_times :
  ?timezone:Timezone.t -> Cron.expr -> from:Ptime.t -> Ptime.t Seq.t
(** Convenience wrapper around [compile] and [fire_times_compiled]. *)

val next_n :
  ?timezone:Timezone.t -> Cron.expr -> from:Ptime.t -> int -> Ptime.t list

val within :
  ?timezone:Timezone.t ->
  Cron.expr ->
  from:Ptime.t ->
  until:Ptime.t ->
  Ptime.t list

val matches : ?timezone:Timezone.t -> Cron.expr -> Ptime.t -> bool
(** Convenience wrapper around [compile] and [matches_compiled]. *)
