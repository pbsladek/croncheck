type warning =
  | NeverFires
  | RarelyFires of { times_per_year : int }
  | DomDowAmbiguity
  | HighFrequency of { per_hour : int }
  | EndOfMonthTrap
  | LeapYearOnly
  | DstAmbiguousHour of { hour : int }

type conflict = { expr_a : string; expr_b : string; at : Ptime.t; delta : int }
type overlap = { started_at : Ptime.t; next_fire : Ptime.t; overrun_by : int }

let add_seconds t seconds = Ptime.add_span t (Ptime.Span.of_int_s seconds)

let seconds_between a b =
  Ptime.diff a b |> Ptime.Span.to_int_s |> Option.value ~default:max_int |> abs

let default_from =
  match Ptime.of_date_time ((2024, 1, 1), ((0, 0, 0), 0)) with
  | Some t -> t
  | None -> invalid_arg "invalid default analysis time"

let count_in_window_until ?limit compiled ~from seconds =
  match add_seconds from seconds with
  | None -> 0
  | Some until -> Schedule.count_within ?limit compiled ~from ~until

let dom_values = function
  | Cron.Posix expr -> Cron.expand expr.dom ~min:1 ~max:31
  | Quartz expr -> Cron.day_field_values expr.dom ~min:1 ~max:31

let fires_per_hour = function
  | Cron.Posix expr -> List.length (Cron.expand expr.minute ~min:0 ~max:59)
  | Quartz expr ->
      List.length (Cron.expand expr.minute ~min:0 ~max:59)
      * List.length (Cron.expand expr.second ~min:0 ~max:59)

let contains_only_gt_28 expr =
  match dom_values expr with [] -> false | xs -> List.for_all (( < ) 28) xs

let includes_feb_29 = function
  | Cron.Posix expr ->
      Cron.expand expr.month ~min:1 ~max:12 = [ 2 ]
      && Cron.expand expr.dom ~min:1 ~max:31 = [ 29 ]
      && expr.dow = Cron.Any
  | Quartz expr ->
      Cron.expand expr.month ~min:1 ~max:12 = [ 2 ]
      && Cron.day_field_values expr.dom ~min:1 ~max:31 = [ 29 ]
      && not (Cron.day_field_is_specific expr.dow)

let has_posix_dom_dow_ambiguity = function
  | Cron.Posix { dom = Any; _ } | Posix { dow = Any; _ } | Quartz _ -> false
  | Posix _ -> true

let hour_field = function
  | Cron.Posix expr -> expr.hour
  | Quartz expr -> expr.hour

let dst_ambiguous_hour_warning timezone expr =
  if not (Timezone.is_dst_observing timezone) then None
  else
    let field = hour_field expr in
    if field = Cron.Any then None
    else
      let hours = Cron.expand field ~min:0 ~max:23 in
      if List.mem 2 hours then Some (DstAmbiguousHour { hour = 2 }) else None

let warn ?(timezone = Timezone.utc) ?(from = default_from) expr =
  let four_years = 366 * 4 * 24 * 60 * 60 in
  let one_year = 366 * 24 * 60 * 60 in
  let compiled = Schedule.compile ~timezone expr in
  let four_year_count =
    count_in_window_until ~limit:1 compiled ~from four_years
  in
  let year_count = count_in_window_until ~limit:12 compiled ~from one_year in
  let per_hour = fires_per_hour expr in
  [
    (if four_year_count = 0 then Some NeverFires else None);
    (if four_year_count > 0 && year_count < 12 then
       Some (RarelyFires { times_per_year = year_count })
     else None);
    (if has_posix_dom_dow_ambiguity expr then Some DomDowAmbiguity else None);
    (if per_hour > 30 then Some (HighFrequency { per_hour }) else None);
    (if contains_only_gt_28 expr then Some EndOfMonthTrap else None);
    (if includes_feb_29 expr then Some LeapYearOnly else None);
    dst_ambiguous_hour_warning timezone expr;
  ]
  |> List.filter_map Fun.id

let conflicts_with_timezone ~timezone ~expr_a ~expr_b ~from ~until ~threshold =
  let a = Schedule.fire_times ~timezone expr_a ~from in
  let b = Schedule.fire_times ~timezone expr_b ~from in
  let next seq =
    match seq () with
    | Seq.Nil -> None
    | Seq.Cons (t, tail) ->
        if Ptime.compare t until > 0 then None else Some (t, tail)
  in
  let rec walk acc a b =
    match (a, b) with
    | None, _ | _, None -> List.rev acc
    | Some (ta, ra), Some (tb, rb) ->
        let delta = seconds_between ta tb in
        if delta <= threshold then
          let at = if Ptime.compare ta tb <= 0 then ta else tb in
          walk
            ({ expr_a = ""; expr_b = ""; at; delta } :: acc)
            (next ra) (next rb)
        else if Ptime.compare ta tb < 0 then walk acc (next ra) b
        else walk acc a (next rb)
  in
  walk [] (next a) (next b)

let conflicts ~expr_a ~expr_b ~from ~until ~threshold =
  conflicts_with_timezone ~timezone:Timezone.utc ~expr_a ~expr_b ~from ~until
    ~threshold

let conflicts_between_fire_times ~expr_a ~expr_b ~threshold a b =
  let rec walk acc a b =
    match (a, b) with
    | [], _ | _, [] -> List.rev acc
    | ta :: ra, tb :: rb ->
        let delta = seconds_between ta tb in
        if delta <= threshold then
          let at = if Ptime.compare ta tb <= 0 then ta else tb in
          walk ({ expr_a; expr_b; at; delta } :: acc) ra rb
        else if Ptime.compare ta tb < 0 then walk acc ra b
        else walk acc a rb
  in
  walk [] a b

let conflicts_between_jobs ~timezone ~from ~until ~threshold job_a job_b =
  let timezone_a = Option.value job_a.Job.timezone ~default:timezone in
  let timezone_b = Option.value job_b.Job.timezone ~default:timezone in
  let a = Schedule.within ~timezone:timezone_a job_a.expr ~from ~until in
  let b = Schedule.within ~timezone:timezone_b job_b.expr ~from ~until in
  conflicts_between_fire_times ~expr_a:(Job.label job_a)
    ~expr_b:(Job.label job_b) ~threshold a b

let overlaps_in_fire_times ~duration times =
  let rec pairs acc = function
    | started_at :: (next_fire :: _ as rest) ->
        let gap = seconds_between next_fire started_at in
        if gap < duration then
          pairs
            ({ started_at; next_fire; overrun_by = duration - gap } :: acc)
            rest
        else pairs acc rest
    | _ -> List.rev acc
  in
  pairs [] times

type diff_side = Left | Right | Both
type diff_entry = { side : diff_side; time : Ptime.t }

let diff ?(timezone = Timezone.utc) expr_a ~expr_b ~from ~until =
  let a = Schedule.fire_times ~timezone expr_a ~from in
  let b = Schedule.fire_times ~timezone expr_b ~from in
  let next seq =
    match seq () with
    | Seq.Nil -> None
    | Seq.Cons (t, tail) ->
        if Ptime.compare t until > 0 then None else Some (t, tail)
  in
  let rec walk acc a b =
    match (a, b) with
    | None, None -> List.rev acc
    | Some (ta, ra), None ->
        walk ({ side = Left; time = ta } :: acc) (next ra) None
    | None, Some (tb, rb) ->
        walk ({ side = Right; time = tb } :: acc) None (next rb)
    | Some (ta, ra), Some (tb, rb) ->
        let cmp = Ptime.compare ta tb in
        if cmp = 0 then
          walk ({ side = Both; time = ta } :: acc) (next ra) (next rb)
        else if cmp < 0 then
          walk ({ side = Left; time = ta } :: acc) (next ra) b
        else walk ({ side = Right; time = tb } :: acc) a (next rb)
  in
  walk [] (next a) (next b)

let overlaps ?(timezone = Timezone.utc) expr ~from ~until ~duration =
  let seq = Schedule.fire_times ~timezone expr ~from in
  let next seq =
    match seq () with
    | Seq.Nil -> None
    | Seq.Cons (t, tail) ->
        if Ptime.compare t until > 0 then None else Some (t, tail)
  in
  let rec loop acc previous rest =
    match next rest with
    | None -> List.rev acc
    | Some (next_fire, tail) ->
        let acc =
          match previous with
          | None -> acc
          | Some started_at ->
              let gap = seconds_between next_fire started_at in
              if gap < duration then
                { started_at; next_fire; overrun_by = duration - gap } :: acc
              else acc
        in
        loop acc (Some next_fire) tail
  in
  loop [] None seq
