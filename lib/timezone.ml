type t = Utc | Fixed_offset of int

let utc = Utc
let offset_seconds = function Utc -> 0 | Fixed_offset seconds -> seconds

let to_string = function
  | Utc -> "UTC"
  | Fixed_offset seconds ->
      let sign = if seconds < 0 then "-" else "+" in
      let abs_seconds = abs seconds in
      let hours = abs_seconds / 3600 in
      let minutes = abs_seconds mod 3600 / 60 in
      Printf.sprintf "%s%02d:%02d" sign hours minutes

let parse_offset s =
  if String.length s <> 6 then None
  else
    let sign =
      match s.[0] with '+' -> Some 1 | '-' -> Some (-1) | _ -> None
    in
    match sign with
    | None -> None
    | Some sign when s.[3] = ':' -> (
        let hours = int_of_string_opt (String.sub s 1 2) in
        let minutes = int_of_string_opt (String.sub s 4 2) in
        match (hours, minutes) with
        | Some h, Some m when h <= 23 && m <= 59 ->
            Some (Fixed_offset (sign * ((h * 3600) + (m * 60))))
        | _ -> None)
    | Some _ -> None

let parse s =
  match String.uppercase_ascii (String.trim s) with
  | "UTC" | "Z" -> Ok Utc
  | normalized -> (
      match parse_offset normalized with
      | Some tz -> Ok tz
      | None ->
          Error
            "unsupported timezone; use UTC, Z, or a fixed offset like +02:00 \
             or -08:00")
