type iana
type t = Utc | Fixed_offset of int | Iana of iana

val utc : t
val offset_seconds : t -> int
val offset_seconds_at : t -> Ptime.t -> int
val local_date_time : t -> Ptime.t -> Ptime.date * Ptime.time

val weekday_of_date :
  Ptime.date -> [ `Fri | `Mon | `Sat | `Sun | `Thu | `Tue | `Wed ]

val instants_of_local_date_time : t -> Ptime.date * Ptime.time -> Ptime.t list
val to_string : t -> string
val parse : string -> (t, string) result
