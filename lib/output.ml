type format = Plain | Json

let string_of_time ?(timezone = Timezone.utc) t =
  Ptime.to_rfc3339 ~tz_offset_s:(Timezone.offset_seconds timezone) t

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

let pp_next ?(timezone = Timezone.utc) ppf ~format ~expr times =
  match format with
  | Plain ->
      Format.fprintf ppf "Next fire times for %s (%s):@." expr
        (Timezone.to_string timezone);
      List.iter
        (fun t -> Format.fprintf ppf "%s@." (string_of_time ~timezone t))
        times
  | Json ->
      `Assoc
        [
          ("expr", `String expr);
          ("timezone", `String (Timezone.to_string timezone));
          ("times", `List (List.map (json_time ~timezone) times));
        ]
      |> pp_json ppf

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

let pp_conflicts ?(timezone = Timezone.utc) ppf ~format conflicts =
  match format with
  | Plain ->
      if conflicts = [] then Format.fprintf ppf "No conflicts found@."
      else
        List.iter
          (fun c ->
            Format.fprintf ppf "conflict at %s (delta %ds)@."
              (string_of_time ~timezone c.Analysis.at)
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

let pp_overlaps ?(timezone = Timezone.utc) ppf ~format overlaps =
  match format with
  | Plain ->
      if overlaps = [] then Format.fprintf ppf "No overlaps found@."
      else
        List.iter
          (fun o ->
            Format.fprintf ppf "started %s, next fire %s, overrun by %ds@."
              (string_of_time ~timezone o.Analysis.started_at)
              (string_of_time ~timezone o.next_fire)
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

let pp_check_plain timezone ppf report =
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
  pp_conflicts ~timezone ppf ~format:Plain report.conflicts;
  if report.overlaps <> [] then
    pp_overlaps ~timezone ppf ~format:Plain report.overlaps

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

let pp_check ~timezone ppf ~format report =
  match format with
  | Plain -> pp_check_plain timezone ppf report
  | Json -> pp_check_json timezone ppf report
