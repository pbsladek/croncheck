type transition = { at : Ptime.t; offset : int }
type iana = { name : string; offsets : int list; transitions : transition list }
type t = Utc | Fixed_offset of int | Iana of iana

let utc = Utc

let zoneinfo_roots =
  [
    "/usr/share/zoneinfo";
    "/var/db/timezone/zoneinfo";
    "/usr/share/lib/zoneinfo";
  ]

let cache : (string, (iana, string) result) Hashtbl.t = Hashtbl.create 16

let valid_iana_name name =
  let len = String.length name in
  let valid_char = function
    | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '-' | '+' | '/' -> true
    | _ -> false
  in
  len > 0
  && (not (String.starts_with ~prefix:"/" name))
  && (not (String.contains name '\\'))
  && (not (String.contains name '.'))
  && String.for_all valid_char name

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let len = in_channel_length ic in
      really_input_string ic len)

let u8 data pos = Char.code data.[pos]

let u32 data pos =
  Int32.(
    logor
      (shift_left (of_int (u8 data pos)) 24)
      (logor
         (shift_left (of_int (u8 data (pos + 1))) 16)
         (logor
            (shift_left (of_int (u8 data (pos + 2))) 8)
            (of_int (u8 data (pos + 3))))))

let i32 data pos = Int32.to_int (u32 data pos)

let i64_to_int i =
  if i > Int64.of_int max_int || i < Int64.of_int min_int then None
  else Some (Int64.to_int i)

let i64 data pos =
  let open Int64 in
  List.fold_left
    (fun acc i ->
      logor acc (shift_left (of_int (u8 data (pos + i))) ((7 - i) * 8)))
    0L [ 0; 1; 2; 3; 4; 5; 6; 7 ]

type header = {
  version : char;
  timecnt : int;
  typecnt : int;
  charcnt : int;
  leapcnt : int;
  ttisstdcnt : int;
  ttisgmtcnt : int;
}

type parsed_block = {
  block_offsets : int list;
  block_transitions : transition list;
  block_end : int;
}

let header_len = 44

let parse_header data pos =
  if String.length data < pos + header_len || String.sub data pos 4 <> "TZif"
  then Error "invalid TZif file"
  else
    Ok
      {
        version = data.[pos + 4];
        ttisgmtcnt = i32 data (pos + 20);
        ttisstdcnt = i32 data (pos + 24);
        leapcnt = i32 data (pos + 28);
        timecnt = i32 data (pos + 32);
        typecnt = i32 data (pos + 36);
        charcnt = i32 data (pos + 40);
      }

let block_len header time_size =
  (header.timecnt * time_size)
  + header.timecnt + (header.typecnt * 6) + header.charcnt
  + (header.leapcnt * (time_size + 4))
  + header.ttisstdcnt + header.ttisgmtcnt

let ptime_of_epoch_s seconds = Ptime.of_span (Ptime.Span.of_int_s seconds)

let parse_block data pos header time_size =
  if header.typecnt <= 0 then Error "timezone has no local time types"
  else
    let needed = pos + block_len header time_size in
    if String.length data < needed then Error "truncated TZif file"
    else
      let transition_pos = pos in
      let index_pos = transition_pos + (header.timecnt * time_size) in
      let ttinfo_pos = index_pos + header.timecnt in
      let read_time i =
        let pos = transition_pos + (i * time_size) in
        match time_size with
        | 4 -> Some (i32 data pos)
        | 8 -> i64_to_int (i64 data pos)
        | _ -> None
      in
      let offsets =
        List.init header.typecnt (fun i -> i32 data (ttinfo_pos + (i * 6)))
      in
      let offset_at index =
        if index < 0 || index >= List.length offsets then None
        else Some (List.nth offsets index)
      in
      let rec loop acc i =
        if i = header.timecnt then Ok (List.rev acc)
        else
          match (read_time i, offset_at (u8 data (index_pos + i))) with
          | Some seconds, Some offset -> (
              match ptime_of_epoch_s seconds with
              | Some at -> loop ({ at; offset } :: acc) (i + 1)
              | None -> loop acc (i + 1))
          | _ -> Error "invalid TZif transition"
      in
      Result.map
        (fun transitions ->
          {
            block_offsets = List.sort_uniq Int.compare offsets;
            block_transitions = transitions;
            block_end = needed;
          })
        (loop [] 0)

type posix_date_rule =
  | Julian_no_leap of int
  | Julian_zero of int
  | Month_week_day of { month : int; week : int; weekday : int }

type posix_rule = { date_rule : posix_date_rule; time_s : int }

type posix_tail = {
  std_offset : int;
  dst_offset : int;
  start_rule : posix_rule;
  end_rule : posix_rule;
}

let is_digit = function '0' .. '9' -> true | _ -> false

let parse_unsigned_int s pos =
  let len = String.length s in
  let rec loop acc i =
    if i < len && is_digit s.[i] then
      loop ((acc * 10) + Char.code s.[i] - Char.code '0') (i + 1)
    else if i = pos then None
    else Some (acc, i)
  in
  loop 0 pos

let skip_tz_name s pos =
  let len = String.length s in
  if pos >= len then None
  else if s.[pos] = '<' then
    match String.index_from_opt s (pos + 1) '>' with
    | None -> None
    | Some end_pos when end_pos = pos + 1 -> None
    | Some end_pos -> Some (end_pos + 1)
  else
    let valid = function 'A' .. 'Z' | 'a' .. 'z' -> true | _ -> false in
    let rec loop i =
      if i < len && valid s.[i] then loop (i + 1)
      else if i = pos then None
      else Some i
    in
    loop pos

let parse_clock s pos =
  let len = String.length s in
  let sign, pos =
    if pos < len then
      match s.[pos] with
      | '+' -> (1, pos + 1)
      | '-' -> (-1, pos + 1)
      | _ -> (1, pos)
    else (1, pos)
  in
  match parse_unsigned_int s pos with
  | None -> None
  | Some (hours, pos) ->
      let read_part pos =
        if pos < len && s.[pos] = ':' then
          match parse_unsigned_int s (pos + 1) with
          | Some (value, next) when value <= 59 -> Some (value, next)
          | _ -> None
        else Some (0, pos)
      in
      let seconds =
        match read_part pos with
        | None -> None
        | Some (minutes, pos) -> (
            match read_part pos with
            | None -> None
            | Some (seconds, pos) ->
                Some (sign * ((hours * 3600) + (minutes * 60) + seconds), pos))
      in
      seconds

let parse_posix_offset s pos =
  parse_clock s pos |> Option.map (fun (seconds, pos) -> (-seconds, pos))

let parse_date_rule s pos =
  let len = String.length s in
  if pos < len && s.[pos] = 'M' then
    match parse_unsigned_int s (pos + 1) with
    | Some (month, dot1) when dot1 < len && s.[dot1] = '.' -> (
        match parse_unsigned_int s (dot1 + 1) with
        | Some (week, dot2) when dot2 < len && s.[dot2] = '.' -> (
            match parse_unsigned_int s (dot2 + 1) with
            | Some (weekday, pos)
              when month >= 1 && month <= 12 && week >= 1 && week <= 5
                   && weekday >= 0 && weekday <= 6 ->
                Some (Month_week_day { month; week; weekday }, pos)
            | _ -> None)
        | _ -> None)
    | _ -> None
  else if pos < len && s.[pos] = 'J' then
    match parse_unsigned_int s (pos + 1) with
    | Some (day, pos) when day >= 1 && day <= 365 ->
        Some (Julian_no_leap day, pos)
    | _ -> None
  else
    match parse_unsigned_int s pos with
    | Some (day, pos) when day >= 0 && day <= 365 -> Some (Julian_zero day, pos)
    | _ -> None

let parse_rule s pos =
  match parse_date_rule s pos with
  | None -> None
  | Some (date_rule, pos) ->
      if pos < String.length s && s.[pos] = '/' then
        Option.map
          (fun (time_s, pos) -> ({ date_rule; time_s }, pos))
          (parse_clock s (pos + 1))
      else Some ({ date_rule; time_s = 2 * 3600 }, pos)

let parse_posix_tail s =
  let len = String.length s in
  match skip_tz_name s 0 with
  | None -> None
  | Some pos -> (
      match parse_posix_offset s pos with
      | None -> None
      | Some (std_offset, pos) -> (
          if pos >= len then None
          else
            match skip_tz_name s pos with
            | None -> None
            | Some pos -> (
                let dst_offset, pos =
                  if pos < len && s.[pos] <> ',' then
                    match parse_posix_offset s pos with
                    | Some parsed -> parsed
                    | None -> (std_offset + 3600, pos)
                  else (std_offset + 3600, pos)
                in
                if pos >= len || s.[pos] <> ',' then None
                else
                  match parse_rule s (pos + 1) with
                  | Some (start_rule, pos) when pos < len && s.[pos] = ',' -> (
                      match parse_rule s (pos + 1) with
                      | Some (end_rule, pos) when pos = len ->
                          Some { std_offset; dst_offset; start_rule; end_rule }
                      | _ -> None)
                  | _ -> None)))

let extract_posix_tail data pos =
  if pos >= String.length data || data.[pos] <> '\n' then None
  else
    match String.index_from_opt data (pos + 1) '\n' with
    | None -> None
    | Some end_pos when end_pos = pos + 1 -> None
    | Some end_pos -> Some (String.sub data (pos + 1) (end_pos - pos - 1))

let leap_year year = year mod 4 = 0 && (year mod 100 <> 0 || year mod 400 = 0)

let days_in_month year = function
  | 1 | 3 | 5 | 7 | 8 | 10 | 12 -> 31
  | 4 | 6 | 9 | 11 -> 30
  | 2 -> if leap_year year then 29 else 28
  | _ -> invalid_arg "invalid month"

let weekday_int_of_date date =
  match Ptime.of_date_time (date, ((0, 0, 0), 0)) with
  | Some t -> (
      match Ptime.weekday t with
      | `Sun -> 0
      | `Mon -> 1
      | `Tue -> 2
      | `Wed -> 3
      | `Thu -> 4
      | `Fri -> 5
      | `Sat -> 6)
  | None -> invalid_arg "invalid date"

let nth_day_of_year year day =
  let rec loop month remaining =
    let days = days_in_month year month in
    if remaining < days then Some (year, month, remaining + 1)
    else if month = 12 then None
    else loop (month + 1) (remaining - days)
  in
  loop 1 day

let date_for_rule year = function
  | Julian_no_leap day ->
      let zero_based = if leap_year year && day >= 60 then day else day - 1 in
      nth_day_of_year year zero_based
  | Julian_zero day -> nth_day_of_year year day
  | Month_week_day { month; week; weekday } ->
      let last_day = days_in_month year month in
      if week = 5 then
        let last_weekday = weekday_int_of_date (year, month, last_day) in
        let day = last_day - ((last_weekday - weekday + 7) mod 7) in
        Some (year, month, day)
      else
        let first_weekday = weekday_int_of_date (year, month, 1) in
        let day =
          1 + ((weekday - first_weekday + 7) mod 7) + ((week - 1) * 7)
        in
        if day <= last_day then Some (year, month, day) else None

let instant_of_local_rule year rule offset =
  match date_for_rule year rule.date_rule with
  | None -> None
  | Some date -> (
      match Ptime.of_date_time (date, ((0, 0, 0), offset)) with
      | None -> None
      | Some midnight ->
          Ptime.add_span midnight (Ptime.Span.of_int_s rule.time_s))

let year_of_time t =
  let (year, _, _), _ = Ptime.to_date_time ~tz_offset_s:0 t in
  year

let future_transitions_from_tail block tail =
  let last_transition =
    match List.rev block.block_transitions with
    | [] -> None
    | transition :: _ -> Some transition
  in
  let first_year =
    match last_transition with
    | None -> 1970
    | Some transition -> year_of_time transition.at
  in
  let last_at = Option.map (fun transition -> transition.at) last_transition in
  let after_last at =
    match last_at with None -> true | Some last -> Ptime.compare at last > 0
  in
  let transitions_for_year year =
    let start =
      instant_of_local_rule year tail.start_rule tail.std_offset
      |> Option.map (fun at -> { at; offset = tail.dst_offset })
    in
    let finish =
      instant_of_local_rule year tail.end_rule tail.dst_offset
      |> Option.map (fun at -> { at; offset = tail.std_offset })
    in
    [ start; finish ] |> List.filter_map Fun.id
  in
  List.init (max 0 (2200 - first_year)) (fun i -> first_year + i)
  |> List.concat_map transitions_for_year
  |> List.filter (fun transition -> after_last transition.at)
  |> List.sort (fun a b -> Ptime.compare a.at b.at)

let parse_tzif name data =
  let ( let* ) = Result.bind in
  let* first = parse_header data 0 in
  let second_header_pos =
    if first.version = '\000' then None
    else Some (header_len + block_len first 4)
  in
  let* block =
    match second_header_pos with
    | None -> parse_block data header_len first 4
    | Some pos ->
        let* second = parse_header data pos in
        parse_block data (pos + header_len) second 8
  in
  let posix_tail =
    Option.bind (extract_posix_tail data block.block_end) parse_posix_tail
  in
  let future_transitions =
    match posix_tail with
    | None -> []
    | Some tail -> future_transitions_from_tail block tail
  in
  let offsets =
    match posix_tail with
    | None -> block.block_offsets
    | Some tail ->
        List.sort_uniq Int.compare
          (tail.std_offset :: tail.dst_offset :: block.block_offsets)
  in
  Ok
    {
      name;
      offsets;
      transitions = block.block_transitions @ future_transitions;
    }

let find_zone_file name =
  List.find_map
    (fun root ->
      let path = Filename.concat root name in
      if Sys.file_exists path && not (Sys.is_directory path) then Some path
      else None)
    zoneinfo_roots

let load_iana name =
  match Hashtbl.find_opt cache name with
  | Some result -> result
  | None ->
      let result =
        if not (valid_iana_name name) then
          Error "invalid timezone name; use an IANA name like America/New_York"
        else
          match find_zone_file name with
          | None ->
              Error
                "unknown timezone; use UTC, Z, a fixed offset like +02:00, or \
                 an IANA name like America/New_York"
          | Some path -> (
              match read_file path with
              | data -> parse_tzif name data
              | exception Sys_error message -> Error message)
      in
      Hashtbl.add cache name result;
      result

let offset_seconds_at timezone t =
  match timezone with
  | Utc -> 0
  | Fixed_offset seconds -> seconds
  | Iana zone ->
      let rec loop current = function
        | [] -> current
        | transition :: rest ->
            if Ptime.compare transition.at t <= 0 then
              loop transition.offset rest
            else current
      in
      let initial = match zone.offsets with offset :: _ -> offset | [] -> 0 in
      loop initial zone.transitions

let offset_seconds = function
  | Utc -> 0
  | Fixed_offset seconds -> seconds
  | Iana _ ->
      invalid_arg
        "IANA timezone offset depends on the instant; use offset_seconds_at"

let local_date_time timezone t =
  Ptime.to_date_time ~tz_offset_s:(offset_seconds_at timezone t) t

let weekday_of_date date =
  match Ptime.of_date_time (date, ((0, 0, 0), 0)) with
  | Some t -> Ptime.weekday t
  | None -> invalid_arg "invalid date"

let same_local_date_time timezone (expected_date, (expected_clock, _)) t =
  let date, (clock, _) = local_date_time timezone t in
  date = expected_date && clock = expected_clock

let instants_of_local_date_time timezone ((date, (clock, _)) as local) =
  let offsets =
    match timezone with
    | Utc -> [ 0 ]
    | Fixed_offset seconds -> [ seconds ]
    | Iana zone -> zone.offsets
  in
  offsets
  |> List.filter_map (fun offset -> Ptime.of_date_time (date, (clock, offset)))
  |> List.filter (same_local_date_time timezone local)
  |> List.sort_uniq Ptime.compare

let to_string = function
  | Utc -> "UTC"
  | Fixed_offset seconds ->
      let sign = if seconds < 0 then "-" else "+" in
      let abs_seconds = abs seconds in
      let hours = abs_seconds / 3600 in
      let minutes = abs_seconds mod 3600 / 60 in
      Printf.sprintf "%s%02d:%02d" sign hours minutes
  | Iana zone -> zone.name

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

let is_dst_observing = function
  | Utc | Fixed_offset _ -> false
  | Iana zone -> List.length zone.offsets > 1

let parse s =
  let raw = String.trim s in
  match String.uppercase_ascii raw with
  | "UTC" | "Z" -> Ok Utc
  | normalized -> (
      match parse_offset normalized with
      | Some tz -> Ok tz
      | None -> Result.map (fun zone -> Iana zone) (load_iana raw))
