type compiled

val compile : ?timezone:Timezone.t -> Cron.expr -> compiled
val matches_compiled : compiled -> Ptime.t -> bool

val fire_times_compiled :
  ?until:Ptime.t -> compiled -> from:Ptime.t -> Ptime.t Seq.t
(** Enumerate times strictly after [from], up to and including [until] when
    supplied. Candidate searches stop at [until], including for sparse
    schedules. *)

val count_within :
  ?limit:int -> compiled -> from:Ptime.t -> until:Ptime.t -> int

val next_n_compiled :
  ?until:Ptime.t -> compiled -> from:Ptime.t -> int -> Ptime.t list
(** Return at most [n] times, stopping at the optional inclusive end boundary.
*)

val within_compiled : compiled -> from:Ptime.t -> until:Ptime.t -> Ptime.t list

val fire_times :
  ?timezone:Timezone.t ->
  ?until:Ptime.t ->
  Cron.expr ->
  from:Ptime.t ->
  Ptime.t Seq.t

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
