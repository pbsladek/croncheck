type iana

type t =
  | Utc
  | Fixed_offset of int
  | Iana of iana
      (** Scheduler timezone. IANA zones are backed by host TZif files, so their
          offsets depend on both the instant and the installed zoneinfo
          database. *)

val utc : t

val offset_seconds : t -> int
(** Return the fixed offset for [Utc] or [Fixed_offset]. Raises
    [Invalid_argument] for IANA zones because their offset is instant-dependent.
*)

val offset_seconds_at : t -> Ptime.t -> int
val local_date_time : t -> Ptime.t -> Ptime.date * Ptime.time

val weekday_of_date :
  Ptime.date -> [ `Fri | `Mon | `Sat | `Sun | `Thu | `Tue | `Wed ]

val instants_of_local_date_time : t -> Ptime.date * Ptime.time -> Ptime.t list
(** Map a local wall-clock time to real instants. The result has length zero for
    DST gaps, one for normal times, and two for DST folds. *)

val is_dst_observing : t -> bool
val to_string : t -> string

val parse : string -> (t, string) result
(** Parse [UTC], [Z], a fixed offset such as [+02:00], or an IANA name such as
    [America/New_York]. *)

val zoneinfo_roots : string list

val zoneinfo_path : string -> string option
(** Resolve the host TZif file for an IANA name without parsing it. *)
