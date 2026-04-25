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
  | DstAmbiguousHour { hour } ->
      Printf.sprintf
        "fires at %02d:xx which falls in a common DST transition window; \
         verify behavior with --tz"
        hour

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

let pp_policy_violations_plain ppf violations =
  if violations <> [] then (
    Format.fprintf ppf "Policy violations:@.";
    List.iter
      (fun v ->
        Format.fprintf ppf "%s: %s@." (Job.label v.Policy.job) v.message)
      violations)

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

let policy_violation_json v =
  `Assoc
    [
      ("job", job_json v.Policy.job);
      ("rule", `String (Policy.rule_to_string v.rule));
      ("message", `String v.message);
    ]

let pp_check_with_policy_json timezone ppf (policy_report : Check.policy_report)
    =
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
  let report = policy_report.report in
  `Assoc
    [
      ("jobs", `List (List.map job_json report.jobs));
      ("warnings", `List (List.map warning_json report.warnings));
      ("conflicts", `List (List.map conflict_json report.conflicts));
      ("overlaps", `List (List.map overlap_json report.overlaps));
      ( "policy_violations",
        `List (List.map policy_violation_json policy_report.policy_violations)
      );
    ]
  |> pp_json ppf

let pp_explain ppf ~format ~expr description =
  match format with
  | Plain -> Format.fprintf ppf "%s@." description
  | Json ->
      `Assoc [ ("expr", `String expr); ("description", `String description) ]
      |> pp_json ppf

let pp_diff ?(timezone = Timezone.utc) ?(time_format = Rfc3339) ppf ~format
    ~expr_a ~expr_b entries =
  match format with
  | Plain ->
      if entries = [] then Format.fprintf ppf "Schedules are identical@."
      else
        List.iter
          (fun e ->
            let marker =
              match e.Analysis.side with
              | Left -> "<"
              | Right -> ">"
              | Both -> "="
            in
            Format.fprintf ppf "%s %s@." marker
              (string_of_time ~timezone ~time_format e.time))
          entries
  | Json ->
      let side_str = function
        | Analysis.Left -> "left"
        | Right -> "right"
        | Both -> "both"
      in
      `Assoc
        [
          ("expr_a", `String expr_a);
          ("expr_b", `String expr_b);
          ("timezone", `String (Timezone.to_string timezone));
          ( "diff",
            `List
              (List.map
                 (fun e ->
                   `Assoc
                     [
                       ("side", `String (side_str e.Analysis.side));
                       ("time", json_time ~timezone e.time);
                     ])
                 entries) );
        ]
      |> pp_json ppf

let pp_load ?(time_format = Rfc3339) ppf ~format report =
  let timezone = report.Load.timezone in
  let busiest = Load.busiest report in
  let job_count_plain job_count =
    Printf.sprintf "%s x%d" (Job.label job_count.Load.job) job_count.fires
  in
  let job_count_json job_count =
    `Assoc
      [
        ("label", `String (Job.label job_count.Load.job));
        ("fires", `Int job_count.fires);
      ]
  in
  match format with
  | Plain ->
      if busiest = [] then Format.fprintf ppf "No scheduled fires found@."
      else (
        Format.fprintf ppf "Busiest %s buckets:@."
          (format_gap_s report.bucket_seconds);
        List.iter
          (fun bucket ->
            Format.fprintf ppf "%s: %d fires (%s)@."
              (string_of_time ~timezone ~time_format bucket.Load.start)
              bucket.fire_count
              (bucket.job_counts |> List.map job_count_plain
             |> String.concat ", "))
          busiest)
  | Json ->
      `Assoc
        [
          ("timezone", `String (Timezone.to_string timezone));
          ("from", json_time ~timezone report.from);
          ("until", json_time ~timezone report.until);
          ("bucket_s", `Int report.bucket_seconds);
          ( "busiest",
            `List
              (List.map
                 (fun bucket ->
                   `Assoc
                     [
                       ("start", json_time ~timezone bucket.Load.start);
                       ("fire_count", `Int bucket.fire_count);
                       ( "jobs",
                         `List (List.map job_count_json bucket.job_counts) );
                     ])
                 busiest) );
        ]
      |> pp_json ppf

let pp_check ~timezone ?(time_format = Rfc3339) ppf ~format report =
  match format with
  | Plain -> pp_check_plain timezone time_format ppf report
  | Json -> pp_check_json timezone ppf report

let pp_check_with_policy ~timezone ?(time_format = Rfc3339) ppf ~format
    policy_report =
  match format with
  | Plain ->
      pp_check_plain timezone time_format ppf policy_report.Check.report;
      pp_policy_violations_plain ppf policy_report.policy_violations
  | Json -> pp_check_with_policy_json timezone ppf policy_report
