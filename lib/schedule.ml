type int_set = { offset : int; values : bool array; members : int list }

type day_rule =
  | Posix_day of { dom_any : bool; dow_any : bool }
  | Quartz_day of { dom_specific : bool; dow_specific : bool }

type compiled = {
  timezone : Timezone.t;
  seconds : int_set option;
  minutes : int_set;
  hours : int_set;
  months : int_set;
  doms : int_set;
  dows : int_set;
  years : int_set option;
  day_rule : day_rule;
  possible : bool;
}

let weekday_to_cron = function
  | `Sun -> 0
  | `Mon -> 1
  | `Tue -> 2
  | `Wed -> 3
  | `Thu -> 4
  | `Fri -> 5
  | `Sat -> 6

let date_time timezone t = Timezone.local_date_time timezone t

let dow timezone t =
  let date, _ = date_time timezone t in
  weekday_to_cron (Timezone.weekday_of_date date)

let make_set ?(normalize = Fun.id) ~min ~max values =
  let set = Array.make (max - min + 1) false in
  List.iter
    (fun value ->
      let value = normalize value in
      if value >= min && value <= max then set.(value - min) <- true)
    values;
  let members =
    Array.to_list set
    |> List.mapi (fun index present ->
           if present then Some (index + min) else None)
    |> List.filter_map Fun.id
  in
  { offset = min; values = set; members }

let set_mem set value =
  let index = value - set.offset in
  index >= 0 && index < Array.length set.values && set.values.(index)

let dow_mem set value = set_mem set value || (value = 0 && set_mem set 7)
let field_set field ~min ~max = make_set ~min ~max (Cron.expand field ~min ~max)
let dow_set field = make_set ~min:0 ~max:7 (Cron.expand field ~min:0 ~max:7)

let day_field_set field ~min ~max =
  make_set ~min ~max (Cron.day_field_values field ~min ~max)

let day_matches compiled ~dom ~dow =
  let dom_match = set_mem compiled.doms dom in
  let dow_match = dow_mem compiled.dows dow in
  match compiled.day_rule with
  | Posix_day { dom_any; dow_any } -> (
      match (dom_any, dow_any) with
      | true, true -> true
      | true, false -> dow_match
      | false, true -> dom_match
      | false, false -> dom_match || dow_match)
  | Quartz_day { dom_specific; dow_specific } -> (
      match (dom_specific, dow_specific) with
      | false, false -> true
      | false, true -> dow_match
      | true, false -> dom_match
      | true, true -> dom_match && dow_match)

let possible compiled =
  let years =
    match compiled.years with
    | Some years -> years.members
    | None -> List.init 400 (( + ) 2000)
  in
  let days = List.init 31 (( + ) 1) in
  List.exists
    (fun y ->
      List.exists
        (fun m ->
          List.exists
            (fun d ->
              let date = (y, m, d) in
              if
                Timezone.instants_of_local_date_time compiled.timezone
                  (date, ((0, 0, 0), 0))
                = []
              then false
              else
                day_matches compiled ~dom:d
                  ~dow:(weekday_to_cron (Timezone.weekday_of_date date)))
            days)
        compiled.months.members)
    years

let compile ?(timezone = Timezone.utc) expr =
  let base =
    match expr with
    | Cron.Posix expr ->
        {
          timezone;
          seconds = None;
          minutes = field_set expr.minute ~min:0 ~max:59;
          hours = field_set expr.hour ~min:0 ~max:23;
          months = field_set expr.month ~min:1 ~max:12;
          doms = field_set expr.dom ~min:1 ~max:31;
          dows = dow_set expr.dow;
          years = None;
          day_rule =
            Posix_day
              { dom_any = expr.dom = Cron.Any; dow_any = expr.dow = Cron.Any };
          possible = true;
        }
    | Cron.Quartz expr ->
        {
          timezone;
          seconds = Some (field_set expr.second ~min:0 ~max:59);
          minutes = field_set expr.minute ~min:0 ~max:59;
          hours = field_set expr.hour ~min:0 ~max:23;
          months = field_set expr.month ~min:1 ~max:12;
          doms = day_field_set expr.dom ~min:1 ~max:31;
          dows =
            make_set ~min:0 ~max:7
              (Cron.day_field_values expr.dow ~min:0 ~max:7);
          years =
            Option.map
              (fun field -> field_set field ~min:1970 ~max:2199)
              expr.year;
          day_rule =
            Quartz_day
              {
                dom_specific = Cron.day_field_is_specific expr.dom;
                dow_specific = Cron.day_field_is_specific expr.dow;
              };
          possible = true;
        }
  in
  { base with possible = possible base }

let matches_compiled compiled t =
  let (year, month, dom), ((hour, minute, second), _tz) =
    date_time compiled.timezone t
  in
  let seconds_match =
    match compiled.seconds with
    | None -> true
    | Some seconds -> set_mem seconds second
  in
  let year_match =
    match compiled.years with None -> true | Some years -> set_mem years year
  in
  seconds_match
  && set_mem compiled.minutes minute
  && set_mem compiled.hours hour
  && set_mem compiled.months month
  && year_match
  && day_matches compiled ~dom ~dow:(dow compiled.timezone t)

let add_seconds t seconds = Ptime.add_span t (Ptime.Span.of_int_s seconds)

let after_last_year compiled t =
  match compiled.years with
  | None -> false
  | Some years -> (
      match List.rev years.members with
      | [] -> true
      | last_year :: _ ->
          let (year, _, _), _ = date_time compiled.timezone t in
          year > last_year)

let next_minute_after timezone t =
  match add_seconds t 60 with
  | None -> None
  | Some bumped ->
      let date, ((hour, minute, _), _) = date_time timezone bumped in
      Timezone.instants_of_local_date_time timezone
        (date, ((hour, minute, 0), 0))
      |> List.find_opt (fun candidate -> Ptime.compare candidate t > 0)

let minute_start timezone t =
  let date, ((hour, minute, _), _) = date_time timezone t in
  Timezone.instants_of_local_date_time timezone (date, ((hour, minute, 0), 0))
  |> List.find_opt (fun candidate -> Ptime.compare candidate t <= 0)

let time_in_minute timezone minute second =
  let date, ((hour, min, _), _) = date_time timezone minute in
  Timezone.instants_of_local_date_time timezone (date, ((hour, min, second), 0))

let minute_matches compiled t =
  let (year, month, dom), ((hour, minute, _), _tz) =
    date_time compiled.timezone t
  in
  let year_match =
    match compiled.years with None -> true | Some years -> set_mem years year
  in
  set_mem compiled.minutes minute
  && set_mem compiled.hours hour
  && set_mem compiled.months month
  && year_match
  && day_matches compiled ~dom ~dow:(dow compiled.timezone t)

let fire_times_compiled compiled ~from =
  if not compiled.possible then Seq.empty
  else
    match compiled.seconds with
    | None ->
        let rec loop cursor () =
          match next_minute_after compiled.timezone cursor with
          | None -> Seq.Nil
          | Some candidate ->
              if after_last_year compiled candidate then Seq.Nil
              else if matches_compiled compiled candidate then
                Seq.Cons (candidate, loop candidate)
              else loop candidate ()
        in
        loop from
    | Some seconds ->
        let rec matching_minute cursor =
          match next_minute_after compiled.timezone cursor with
          | None -> None
          | Some minute ->
              if after_last_year compiled minute then None
              else if minute_matches compiled minute then Some minute
              else matching_minute minute
        in
        let candidates_after cursor minute =
          seconds.members
          |> List.concat_map (time_in_minute compiled.timezone minute)
          |> List.filter (fun t -> Ptime.compare t cursor > 0)
        in
        let rec loop cursor pending () =
          match pending with
          | t :: rest -> Seq.Cons (t, loop t rest)
          | [] -> (
              let current_candidates =
                match minute_start compiled.timezone cursor with
                | Some minute when minute_matches compiled minute ->
                    candidates_after cursor minute
                | _ -> []
              in
              if current_candidates <> [] then loop cursor current_candidates ()
              else
                match matching_minute cursor with
                | None -> Seq.Nil
                | Some minute -> loop cursor (candidates_after cursor minute) ()
              )
        in
        loop from []

let count_within ?limit compiled ~from ~until =
  let rec loop count seq =
    match limit with
    | Some limit when count >= limit -> count
    | _ -> (
        match seq () with
        | Seq.Nil -> count
        | Seq.Cons (t, tail) ->
            if Ptime.compare t until > 0 then count else loop (count + 1) tail)
  in
  loop 0 (fire_times_compiled compiled ~from)

let next_n_compiled compiled ~from n =
  if n <= 0 then []
  else
    let rec loop acc left seq =
      if left = 0 then List.rev acc
      else
        match seq () with
        | Seq.Nil -> List.rev acc
        | Seq.Cons (t, tail) -> loop (t :: acc) (left - 1) tail
    in
    loop [] n (fire_times_compiled compiled ~from)

let within_compiled compiled ~from ~until =
  let rec loop acc seq =
    match seq () with
    | Seq.Nil -> List.rev acc
    | Seq.Cons (t, tail) ->
        if Ptime.compare t until > 0 then List.rev acc else loop (t :: acc) tail
  in
  loop [] (fire_times_compiled compiled ~from)

let fire_times ?(timezone = Timezone.utc) expr ~from =
  fire_times_compiled (compile ~timezone expr) ~from

let next_n ?(timezone = Timezone.utc) expr ~from n =
  next_n_compiled (compile ~timezone expr) ~from n

let within ?(timezone = Timezone.utc) expr ~from ~until =
  within_compiled (compile ~timezone expr) ~from ~until

let matches ?(timezone = Timezone.utc) expr t =
  matches_compiled (compile ~timezone expr) t
