type warning =
  | NeverFires
  | RarelyFires of { times_per_year : int }
  | DomDowAmbiguity
  | HighFrequency of { per_hour : int }
  | EndOfMonthTrap
  | LeapYearOnly
  | DstAmbiguousHour of { hour : int }

val warn : ?timezone:Timezone.t -> ?from:Ptime.t -> Cron.expr -> warning list

type conflict = { expr_a : string; expr_b : string; at : Ptime.t; delta : int }

val conflicts :
  expr_a:Cron.expr ->
  expr_b:Cron.expr ->
  from:Ptime.t ->
  until:Ptime.t ->
  threshold:int ->
  conflict list

val conflicts_with_timezone :
  timezone:Timezone.t ->
  expr_a:Cron.expr ->
  expr_b:Cron.expr ->
  from:Ptime.t ->
  until:Ptime.t ->
  threshold:int ->
  conflict list

val conflicts_between_jobs :
  timezone:Timezone.t ->
  from:Ptime.t ->
  until:Ptime.t ->
  threshold:int ->
  Job.t ->
  Job.t ->
  conflict list

val conflicts_between_fire_times :
  expr_a:string ->
  expr_b:string ->
  threshold:int ->
  Ptime.t list ->
  Ptime.t list ->
  conflict list

type overlap = { started_at : Ptime.t; next_fire : Ptime.t; overrun_by : int }

val overlaps_in_fire_times : duration:int -> Ptime.t list -> overlap list

val overlaps :
  ?timezone:Timezone.t ->
  Cron.expr ->
  from:Ptime.t ->
  until:Ptime.t ->
  duration:int ->
  overlap list

type diff_side = Left | Right | Both
type diff_entry = { side : diff_side; time : Ptime.t }

val diff :
  ?timezone:Timezone.t ->
  Cron.expr ->
  expr_b:Cron.expr ->
  from:Ptime.t ->
  until:Ptime.t ->
  diff_entry list
