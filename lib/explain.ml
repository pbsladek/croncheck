open Cron

let ordinal n =
  match n mod 100 with
  | 11 | 12 | 13 -> Printf.sprintf "%dth" n
  | _ -> (
      match n mod 10 with
      | 1 -> Printf.sprintf "%dst" n
      | 2 -> Printf.sprintf "%dnd" n
      | 3 -> Printf.sprintf "%drd" n
      | _ -> Printf.sprintf "%dth" n)

let month_name = Util.month_name

let dow_name = function
  | 0 | 7 -> "Sunday"
  | 1 -> "Monday"
  | 2 -> "Tuesday"
  | 3 -> "Wednesday"
  | 4 -> "Thursday"
  | 5 -> "Friday"
  | 6 -> "Saturday"
  | _ -> "?"

let fmt_time h m =
  if h = 0 && m = 0 then "midnight"
  else if h = 12 && m = 0 then "noon"
  else
    let h12 = if h mod 12 = 0 then 12 else h mod 12 in
    let mer = if h < 12 then "AM" else "PM" in
    if m = 0 then Printf.sprintf "%d:00 %s" h12 mer
    else Printf.sprintf "%d:%02d %s" h12 m mer

let describe_time minute hour =
  match (minute, hour) with
  | Any, Any -> "every minute"
  | Step (Any, n), Any -> Printf.sprintf "every %d minutes" n
  | Value 0, Any -> "at the top of every hour"
  | Value m, Any -> Printf.sprintf "at minute %d of every hour" m
  | Value m, Value h -> Printf.sprintf "at %s" (fmt_time h m)
  | Step (Any, n), Value h ->
      Printf.sprintf "every %d minutes during hour %d" n h
  | Any, Value h -> Printf.sprintf "every minute during hour %d" h
  | _ ->
      let mins = Cron.expand minute ~min:0 ~max:59 in
      let hrs = Cron.expand hour ~min:0 ~max:23 in
      let show xs = String.concat ", " (List.map string_of_int xs) in
      Printf.sprintf "at minute(s) %s of hour(s) %s" (show mins) (show hrs)

let describe_list_field field ~min ~max ~name_fn =
  match field with
  | Any -> None
  | Value n -> Some (name_fn n)
  | Range (lo, hi) ->
      Some (Printf.sprintf "%s through %s" (name_fn lo) (name_fn hi))
  | _ ->
      let vals = Cron.expand field ~min ~max in
      Some (String.concat ", " (List.map name_fn vals))

let describe_dom f = describe_list_field f ~min:1 ~max:31 ~name_fn:ordinal
let describe_month f = describe_list_field f ~min:1 ~max:12 ~name_fn:month_name

let describe_dow f =
  match f with
  | List _ | Step _ ->
      Cron.expand f ~min:0 ~max:7
      |> List.map (fun n -> if n = 7 then 0 else n)
      |> List.sort_uniq Int.compare |> List.map dow_name |> String.concat ", "
      |> Option.some
  | _ -> describe_list_field f ~min:0 ~max:6 ~name_fn:dow_name

let combine ?(day_join = "or") time dom_opt dow_opt month_opt =
  let day_part =
    match (dom_opt, dow_opt) with
    | None, None -> ""
    | Some d, None -> Printf.sprintf " on %s" d
    | None, Some w -> Printf.sprintf " on %s" w
    | Some d, Some w -> Printf.sprintf " on %s %s %s" d day_join w
  in
  let month_part =
    match month_opt with None -> "" | Some m -> Printf.sprintf " in %s" m
  in
  time ^ day_part ^ month_part

let describe = function
  | Posix p ->
      let time = describe_time p.minute p.hour in
      let dom = describe_dom p.dom in
      let month = describe_month p.month in
      let dow = describe_dow p.dow in
      combine time dom dow month
  | Quartz q ->
      let time = describe_time q.minute q.hour in
      let seconds =
        match q.second with
        | Any -> " at every second"
        | field ->
            let values = Cron.expand field ~min:0 ~max:59 in
            Printf.sprintf " at second(s) %s"
              (String.concat ", " (List.map string_of_int values))
      in
      let dom =
        match q.dom with Specific f -> describe_dom f | No_specific -> None
      in
      let dow =
        match q.dow with Specific f -> describe_dow f | No_specific -> None
      in
      let month = describe_month q.month in
      let years =
        match q.year with
        | None -> ""
        | Some Any -> " in years 1970 through 2199"
        | Some field ->
            let years =
              describe_list_field field ~min:1970 ~max:2199
                ~name_fn:string_of_int
            in
            " in year(s) " ^ Option.value years ~default:""
      in
      combine ~day_join:"and" (time ^ seconds) dom dow month ^ years
