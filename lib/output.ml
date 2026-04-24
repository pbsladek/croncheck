type format = Plain | Json
type time_format = Rfc3339 | Human

let month_name = Util.month_name

let weekday_name = function
  | `Mon -> "Mon"
  | `Tue -> "Tue"
  | `Wed -> "Wed"
  | `Thu -> "Thu"
  | `Fri -> "Fri"
  | `Sat -> "Sat"
  | `Sun -> "Sun"

let human_hour hour = match hour mod 12 with 0 -> 12 | hour -> hour
let meridiem hour = if hour < 12 then "AM" else "PM"

let human_time timezone t =
  let (year, month, day), ((hour, minute, second), _tz) =
    Timezone.local_date_time timezone t
  in
  let weekday = Timezone.weekday_of_date (year, month, day) in
  let time =
    if second = 0 then
      Printf.sprintf "%d:%02d %s" (human_hour hour) minute (meridiem hour)
    else
      Printf.sprintf "%d:%02d:%02d %s" (human_hour hour) minute second
        (meridiem hour)
  in
  Printf.sprintf "%s %d %s %d at %s %s" (month_name month) day
    (weekday_name weekday) year time
    (Timezone.to_string timezone)

let string_of_time ?(timezone = Timezone.utc) ?(time_format = Rfc3339) t =
  match time_format with
  | Rfc3339 ->
      Ptime.to_rfc3339 ~tz_offset_s:(Timezone.offset_seconds_at timezone t) t
  | Human -> human_time timezone t

let warning_to_string = function
  | Analysis.NeverFires -> "never fires"
  | RarelyFires { times_per_year } ->
      Printf.sprintf "rarely fires (%d times/year)" times_per_year
  | DomDowAmbiguity ->
      "day-of-month and day-of-week both restricted; POSIX cron uses OR \
       semantics"
  | HighFrequency { per_hour } ->
      Printf.sprintf "high frequency (%d times/hour)" per_hour
  | EndOfMonthTrap ->
      "end-of-month trap; selected days do not occur every month"
  | LeapYearOnly -> "leap-year-only schedule"

let json_time ?(timezone = Timezone.utc) t =
  `String (string_of_time ~timezone t)

let pp_json ppf json =
  Format.pp_print_string ppf (Yojson.Safe.pretty_to_string json);
  Format.pp_print_newline ppf ()

type gap_stats = { count : int; min_s : int; max_s : int; avg_s : int }

let compute_gaps times =
  let rec diffs = function
    | [] | [ _ ] -> []
    | a :: (b :: _ as rest) ->
        let s =
          Ptime.diff b a |> Ptime.Span.to_int_s |> Option.value ~default:0
        in
        s :: diffs rest
  in
  match diffs times with
  | [] -> None
  | first :: rest ->
      let count, min_s, max_s, sum =
        List.fold_left
          (fun (n, mn, mx, s) d -> (n + 1, min mn d, max mx d, s + d))
          (1, first, first, first) rest
      in
      Some { count; min_s; max_s; avg_s = sum / count }

let format_gap_s s =
  if s < 60 then Printf.sprintf "%ds" s
  else if s < 3600 then
    let m = s / 60 and r = s mod 60 in
    if r = 0 then Printf.sprintf "%dm" m else Printf.sprintf "%dm %ds" m r
  else
    let h = s / 3600 and rm = s mod 3600 in
    let m = rm / 60 and r = rm mod 60 in
    if rm = 0 then Printf.sprintf "%dh" h
    else if r = 0 then Printf.sprintf "%dh %dm" h m
    else Printf.sprintf "%dh %dm %ds" h m r

let pp_next ?(timezone = Timezone.utc) ?(time_format = Rfc3339) ?(gaps = false)
    ppf ~format ~expr times =
  let gap_stats = if gaps then compute_gaps times else None in
  match format with
  | Plain ->
      Format.fprintf ppf "Next fire times for %s (%s):@." expr
        (Timezone.to_string timezone);
      List.iter
        (fun t ->
          Format.fprintf ppf "%s@." (string_of_time ~timezone ~time_format t))
        times;
      Option.iter
        (fun g ->
          Format.fprintf ppf "Gaps: min %s, max %s, avg %s@."
            (format_gap_s g.min_s) (format_gap_s g.max_s) (format_gap_s g.avg_s))
        gap_stats
  | Json ->
      let base =
        [
          ("expr", `String expr);
          ("timezone", `String (Timezone.to_string timezone));
          ("times", `List (List.map (json_time ~timezone) times));
        ]
      in
      let assoc =
        match gap_stats with
        | None -> base
        | Some g ->
            base
            @ [
                ( "gaps",
                  `Assoc
                    [
                      ("count", `Int g.count);
                      ("min_s", `Int g.min_s);
                      ("max_s", `Int g.max_s);
                      ("avg_s", `Int g.avg_s);
                    ] );
              ]
      in
      `Assoc assoc |> pp_json ppf

let pp_warnings ppf ~format ~expr warnings =
  match format with
  | Plain ->
      if warnings = [] then Format.fprintf ppf "No warnings for %s@." expr
      else (
        Format.fprintf ppf "Warnings for %s:@." expr;
        List.iter
          (fun w -> Format.fprintf ppf "- %s@." (warning_to_string w))
          warnings)
  | Json ->
      `Assoc
        [
          ("expr", `String expr);
          ( "warnings",
            `List (List.map (fun w -> `String (warning_to_string w)) warnings)
          );
        ]
      |> pp_json ppf

let pp_conflicts ?(timezone = Timezone.utc) ?(time_format = Rfc3339) ppf ~format
    conflicts =
  match format with
  | Plain ->
      if conflicts = [] then Format.fprintf ppf "No conflicts found@."
      else
        List.iter
          (fun c ->
            Format.fprintf ppf "conflict at %s (delta %ds)@."
              (string_of_time ~timezone ~time_format c.Analysis.at)
              c.delta)
          conflicts
  | Json ->
      `Assoc
        [
          ( "conflicts",
            `List
              (List.map
                 (fun c ->
                   `Assoc
                     [
                       ("at", json_time ~timezone c.Analysis.at);
                       ("delta", `Int c.delta);
                       ("expr_a", `String c.expr_a);
                       ("expr_b", `String c.expr_b);
                     ])
                 conflicts) );
        ]
      |> pp_json ppf

let pp_overlaps ?(timezone = Timezone.utc) ?(time_format = Rfc3339) ppf ~format
    overlaps =
  match format with
  | Plain ->
      if overlaps = [] then Format.fprintf ppf "No overlaps found@."
      else
        List.iter
          (fun o ->
            Format.fprintf ppf "started %s, next fire %s, overrun by %ds@."
              (string_of_time ~timezone ~time_format o.Analysis.started_at)
              (string_of_time ~timezone ~time_format o.next_fire)
              o.overrun_by)
          overlaps
  | Json ->
      `Assoc
        [
          ( "overlaps",
            `List
              (List.map
                 (fun o ->
                   `Assoc
                     [
                       ("started_at", json_time ~timezone o.Analysis.started_at);
                       ("next_fire", json_time ~timezone o.next_fire);
                       ("overrun_by", `Int o.overrun_by);
                     ])
                 overlaps) );
        ]
      |> pp_json ppf

let job_json job =
  `Assoc
    [
      ("label", `String (Job.label job));
      ("expr", `String job.Job.expr_raw);
      ("source", `String (Job.source_to_string job.source));
      ("line", match job.line with Some line -> `Int line | None -> `Null);
      ( "command",
        match job.command with Some command -> `String command | None -> `Null
      );
      ( "timezone",
        match job.timezone with
        | Some timezone -> `String (Timezone.to_string timezone)
        | None -> `Null );
    ]

let pp_check_plain timezone time_format ppf report =
  if report.Check.jobs = [] then Format.fprintf ppf "No jobs found@.";
  List.iter
    (fun (job, warnings) ->
      if warnings <> [] then (
        Format.fprintf ppf "%s: %s@." (Job.label job) job.Job.expr_raw;
        List.iter
          (fun warning ->
            Format.fprintf ppf "- %s@." (warning_to_string warning))
          warnings))
    report.warnings;
  pp_conflicts ~timezone ~time_format ppf ~format:Plain report.conflicts;
  if report.overlaps <> [] then
    pp_overlaps ~timezone ~time_format ppf ~format:Plain report.overlaps

let pp_check_json timezone ppf (report : Check.report) =
  let warning_json (job, warnings) =
    `Assoc
      [
        ("job", job_json job);
        ( "warnings",
          `List
            (List.map
               (fun warning -> `String (warning_to_string warning))
               warnings) );
      ]
  in
  let conflict_json c =
    `Assoc
      [
        ("expr_a", `String c.Analysis.expr_a);
        ("expr_b", `String c.expr_b);
        ("at", json_time ~timezone c.at);
        ("delta", `Int c.delta);
      ]
  in
  let overlap_json o =
    `Assoc
      [
        ("started_at", json_time ~timezone o.Analysis.started_at);
        ("next_fire", json_time ~timezone o.next_fire);
        ("overrun_by", `Int o.overrun_by);
      ]
  in
  `Assoc
    [
      ("jobs", `List (List.map job_json report.jobs));
      ("warnings", `List (List.map warning_json report.warnings));
      ("conflicts", `List (List.map conflict_json report.conflicts));
      ("overlaps", `List (List.map overlap_json report.overlaps));
    ]
  |> pp_json ppf

let pp_explain ppf ~format ~expr description =
  match format with
  | Plain -> Format.fprintf ppf "%s@." description
  | Json ->
      `Assoc [ ("expr", `String expr); ("description", `String description) ]
      |> pp_json ppf

let pp_check ~timezone ?(time_format = Rfc3339) ppf ~format report =
  match format with
  | Plain -> pp_check_plain timezone time_format ppf report
  | Json -> pp_check_json timezone ppf report
