type compiled
(** Expanded schedule ready for repeated matching or enumeration. Compilation
    fixes the timezone and precomputes field membership. *)

val compile : ?timezone:Timezone.t -> Cron.expr -> compiled

val matches_compiled : compiled -> Ptime.t -> bool
(** [matches_compiled c t] tests [t] against the local wall time selected by
    [c]'s timezone. *)

val fire_times_compiled :
  ?until:Ptime.t -> compiled -> from:Ptime.t -> Ptime.t Seq.t
(** Enumerate times strictly after [from], up to and including [until] when
    supplied. Candidate searches stop at [until], including for sparse
    schedules. *)

val count_within :
  ?limit:int -> compiled -> from:Ptime.t -> until:Ptime.t -> int
(** Count fires strictly after [from] and at or before [until], stopping early
    at [limit] when supplied. *)

val next_n_compiled :
  ?until:Ptime.t -> compiled -> from:Ptime.t -> int -> Ptime.t list
(** Return at most [n] times, stopping at the optional inclusive end boundary.
*)

val within_compiled : compiled -> from:Ptime.t -> until:Ptime.t -> Ptime.t list
(** Enumerate fires strictly after [from] and at or before [until]. Returned
    instants are ascending and deduplicated. *)

val fire_times :
  ?timezone:Timezone.t ->
  ?until:Ptime.t ->
  Cron.expr ->
  from:Ptime.t ->
  Ptime.t Seq.t
(** Convenience wrapper around [compile] and [fire_times_compiled]. *)

val next_n :
  ?timezone:Timezone.t ->
  ?until:Ptime.t ->
  Cron.expr ->
  from:Ptime.t ->
  int ->
  Ptime.t list

val within :
  ?timezone:Timezone.t ->
  Cron.expr ->
  from:Ptime.t ->
  until:Ptime.t ->
  Ptime.t list

val matches : ?timezone:Timezone.t -> Cron.expr -> Ptime.t -> bool
(** Convenience wrapper around [compile] and [matches_compiled]. *)
