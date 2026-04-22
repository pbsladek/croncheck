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

type spec = {
  name : string;
  min : int;
  max : int;
  normalize : int -> int;
  aliases : (string * int) list;
}

let ( let* ) = Result.bind
let ( let+ ) result f = Result.map f result

let parse_error_to_string = function
  | InvalidFieldCount n ->
      Printf.sprintf "expected 5 POSIX fields or 6/7 Quartz fields, got %d" n
  | FieldOutOfRange (name, value, min, max) ->
      Printf.sprintf "%s value %d is outside allowed range %d-%d" name value min
        max
  | InvalidSyntax (name, raw) ->
      Printf.sprintf "invalid syntax in %s field: %S" name raw

let split_nonempty_on ch s =
  match String.split_on_char ch s with
  | [] -> None
  | parts when List.exists (( = ) "") parts -> None
  | parts -> Some parts

let validate_value spec n =
  if n < spec.min || n > spec.max then
    Error (FieldOutOfRange (spec.name, n, spec.min, spec.max))
  else Ok (spec.normalize n)

let parse_atom spec raw =
  match int_of_string_opt raw with
  | Some n ->
      let+ normalized = validate_value spec n in
      (n, normalized)
  | None -> (
      match List.assoc_opt (String.uppercase_ascii raw) spec.aliases with
      | Some n -> Ok (n, n)
      | None -> Error (InvalidSyntax (spec.name, raw)))

let parse_base spec raw =
  match split_nonempty_on '-' raw with
  | None -> Error (InvalidSyntax (spec.name, raw))
  | Some [ "*" ] -> Ok Any
  | Some [ atom ] ->
      let+ _, normalized = parse_atom spec atom in
      Value normalized
  | Some [ lo; hi ] -> (
      let* lo, _ = parse_atom spec lo in
      let* hi, _ = parse_atom spec hi in
      match lo <= hi with
      | true -> Ok (Range (lo, hi))
      | false -> Error (InvalidSyntax (spec.name, raw)))
  | Some _ -> Error (InvalidSyntax (spec.name, raw))

let parse_part spec raw =
  match split_nonempty_on '/' raw with
  | None -> Error (InvalidSyntax (spec.name, raw))
  | Some [ base ] -> parse_base spec base
  | Some [ base; step ] -> (
      match int_of_string_opt step with
      | Some n when n > 0 ->
          let+ field = parse_base spec base in
          Step (field, n)
      | _ -> Error (InvalidSyntax (spec.name, raw)))
  | Some _ -> Error (InvalidSyntax (spec.name, raw))

let parse_field spec raw =
  match split_nonempty_on ',' raw with
  | None -> Error (InvalidSyntax (spec.name, raw))
  | Some [ one ] -> parse_part spec one
  | Some parts ->
      let rec loop acc = function
        | [] -> Ok (List (List.rev acc))
        | part :: rest ->
            let* field = parse_part spec part in
            loop (field :: acc) rest
      in
      loop [] parts

let parse_day_field spec raw =
  match raw with
  | "?" -> Ok No_specific
  | _ ->
      let+ field = parse_field spec raw in
      Specific field

let day_field_is_specific = function Specific _ -> true | No_specific -> false

let spec ?(aliases = []) name min max =
  { name; min; max; normalize = Fun.id; aliases }

let month_aliases =
  [
    ("JAN", 1);
    ("FEB", 2);
    ("MAR", 3);
    ("APR", 4);
    ("MAY", 5);
    ("JUN", 6);
    ("JUL", 7);
    ("AUG", 8);
    ("SEP", 9);
    ("OCT", 10);
    ("NOV", 11);
    ("DEC", 12);
  ]

let dow_aliases =
  [
    ("SUN", 0);
    ("MON", 1);
    ("TUE", 2);
    ("WED", 3);
    ("THU", 4);
    ("FRI", 5);
    ("SAT", 6);
  ]

let dow_spec =
  {
    name = "day-of-week";
    min = 0;
    max = 7;
    normalize = (fun n -> if n = 7 then 0 else n);
    aliases = dow_aliases;
  }

let minute_spec = spec "minute" 0 59
let second_spec = spec "second" 0 59
let hour_spec = spec "hour" 0 23
let dom_spec = spec "day-of-month" 1 31
let month_spec = spec ~aliases:month_aliases "month" 1 12
let year_spec = spec "year" 1970 2199

let macro_expansion = function
  | "@yearly" | "@annually" -> Some "0 0 1 1 *"
  | "@monthly" -> Some "0 0 1 * *"
  | "@weekly" -> Some "0 0 * * 0"
  | "@daily" | "@midnight" -> Some "0 0 * * *"
  | "@hourly" -> Some "0 * * * *"
  | _ -> None

let parse_posix_fields = function
  | [ minute; hour; dom; month; dow ] ->
      let* minute = parse_field minute_spec minute in
      let* hour = parse_field hour_spec hour in
      let* dom = parse_field dom_spec dom in
      let* month = parse_field month_spec month in
      let+ dow = parse_field dow_spec dow in
      Posix { minute; hour; dom; month; dow }
  | fields -> Error (InvalidFieldCount (List.length fields))

let parse_posix s = parse_posix_fields (Util.split_words s)

let parse_quartz_fields = function
  | ( [ second; minute; hour; dom; month; dow ]
    | [ second; minute; hour; dom; month; dow; _ ] ) as fields ->
      let year =
        match fields with [ _; _; _; _; _; _; year ] -> Some year | _ -> None
      in
      let* second = parse_field second_spec second in
      let* minute = parse_field minute_spec minute in
      let* hour = parse_field hour_spec hour in
      let* dom = parse_day_field dom_spec dom in
      let* month = parse_field month_spec month in
      let* dow = parse_day_field dow_spec dow in
      let* year =
        match year with
        | None -> Ok None
        | Some raw ->
            let+ field = parse_field year_spec raw in
            Some field
      in
      if (not (day_field_is_specific dom)) && not (day_field_is_specific dow)
      then Error (InvalidSyntax ("day-of-month/day-of-week", "? ?"))
      else Ok (Quartz { second; minute; hour; dom; month; dow; year })
  | fields -> Error (InvalidFieldCount (List.length fields))

let parse_quartz s = parse_quartz_fields (Util.split_words s)

let parse s =
  let s = String.trim s in
  match macro_expansion (String.lowercase_ascii s) with
  | Some expanded -> parse_posix expanded
  | None when String.starts_with ~prefix:"@" s ->
      Error (InvalidSyntax ("macro", s))
  | None -> (
      let fields = Util.split_words s in
      match List.length fields with
      | 5 -> parse_posix_fields fields
      | 6 | 7 -> parse_quartz_fields fields
      | n -> Error (InvalidFieldCount n))

let rec expand field ~min ~max =
  let range lo hi =
    if lo > hi then [] else List.init (hi - lo + 1) (( + ) lo)
  in
  match field with
  | Any -> range min max
  | Value n -> if n >= min && n <= max then [ n ] else []
  | Range (lo, hi) -> range (Stdlib.max min lo) (Stdlib.min max hi)
  | Step (base, step) ->
      let values = expand base ~min ~max in
      let origin = match values with [] -> min | first :: _ -> first in
      List.filter (fun n -> (n - origin) mod step = 0) values
  | List fields ->
      fields |> List.concat_map (expand ~min ~max) |> List.sort_uniq Int.compare

let day_field_values field ~min ~max =
  match field with
  | Specific field -> expand field ~min ~max
  | No_specific -> expand Any ~min ~max
