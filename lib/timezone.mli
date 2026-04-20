type t =
  | Utc
  | Fixed_offset of int

val utc : t
val offset_seconds : t -> int
val to_string : t -> string
val parse : string -> (t, string) result

