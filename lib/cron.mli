type field =
  | Any
  | Value of int
  | Range of int * int
  | Step of field * int
  | List of field list

type day_field = Specific of field | No_specific

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

type expr = Posix of posix | Quartz of quartz

type parse_error =
  | InvalidFieldCount of int
  | FieldOutOfRange of string * int * int * int
  | InvalidSyntax of string * string

val parse : string -> (expr, parse_error) result
val parse_posix : string -> (expr, parse_error) result
val parse_quartz : string -> (expr, parse_error) result
val macro_expansion : string -> string option
val expand : field -> min:int -> max:int -> int list
val day_field_values : day_field -> min:int -> max:int -> int list
val day_field_is_specific : day_field -> bool
val parse_error_to_string : parse_error -> string
