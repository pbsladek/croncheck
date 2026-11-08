type field =
  | Any
  | Value of int
  | Range of int * int
  | Step of field * int
  | List of field list
      (** A cron field before expansion. The bounds are not part of the value;
          callers supply them when expanding because the same shape is used for
          minutes, hours, months, and days. *)

type day_field =
  | Specific of field
  | No_specific
      (** Quartz uses [?] to say that one of day-of-month or day-of-week is not
          part of the match. This is distinct from [*], which is an explicit
          wildcard. *)

type posix = {
  minute : field;
  hour : field;
  dom : field;
  month : field;
  dow : field;
}

type quartz = {
  second : field;
  minute : field;
  hour : field;
  dom : day_field;
  month : field;
  dow : day_field;
  year : field option;
}

type expr =
  | Posix of posix
  | Quartz of quartz
      (** A parsed recurring schedule. Event-like macros such as [@reboot] are
          not represented because they cannot be evaluated as future instants.
      *)

type parse_error =
  | InvalidFieldCount of int
  | FieldOutOfRange of string * int * int * int
  | InvalidSyntax of string * string

val parse : string -> (expr, parse_error) result
(** Parse either a POSIX 5-field expression or a Quartz 6/7-field expression.
    The parser validates syntax and field ranges, but leaves calendar
    feasibility and operational warnings to [Analysis]. *)

val parse_posix : string -> (expr, parse_error) result
val parse_quartz : string -> (expr, parse_error) result
val macro_expansion : string -> string option

val expand : field -> min:int -> max:int -> int list
(** [expand field ~min ~max] returns the sorted values selected by [field] in
    the closed interval [[min], [max]]. Duplicate spellings collapse here so
    downstream schedule generation is deterministic. *)

val day_field_values : day_field -> min:int -> max:int -> int list
val day_field_is_specific : day_field -> bool
val parse_error_to_string : parse_error -> string
