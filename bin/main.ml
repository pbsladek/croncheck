open Cmdliner

let parse_expr raw =
  match Croncheck_lib.Cron.parse raw with
  | Ok expr -> Ok expr
  | Error e -> Error (`Msg (Croncheck_lib.Cron.parse_error_to_string e))

let print_error ?hint message =
  Format.eprintf "Error: %s@." message;
  Option.iter (fun h -> Format.eprintf "Hint: %s@." h) hint

let print_parse_error ~expr reason =
  Format.eprintf "Error: invalid cron expression@.";
  Format.eprintf "  expression: %s@." expr;
  Format.eprintf "  reason: %s@." reason

let print_input_errors errors =
  Format.eprintf "Error: failed to parse input@.";
  List.iter (fun e -> Format.eprintf "  - %s@." e) errors

let format_conv =
  let parse = function
    | "plain" -> Ok Croncheck_lib.Output.Plain
    | "json" -> Ok Json
    | other ->
        Error
          (`Msg
             (Printf.sprintf "expected output format 'plain' or 'json', got %S"
                other))
  in
  let print ppf = function
    | Croncheck_lib.Output.Plain -> Format.pp_print_string ppf "plain"
    | Json -> Format.pp_print_string ppf "json"
  in
  Arg.conv (parse, print)

let time_format_conv =
  let parse = function
    | "rfc3339" -> Ok Croncheck_lib.Output.Rfc3339
    | "human" -> Ok Human
    | other ->
        Error
          (`Msg
             (Printf.sprintf "expected time format 'rfc3339' or 'human', got %S"
                other))
  in
  let print ppf = function
    | Croncheck_lib.Output.Rfc3339 -> Format.pp_print_string ppf "rfc3339"
    | Human -> Format.pp_print_string ppf "human"
  in
  Arg.conv (parse, print)

let parse_duration s =
  let len = String.length s in
  if len = 0 then Error (`Msg "expected duration like 30s, 24h, or 7d")
  else
    let unit_char = s.[len - 1] in
    let number, factor =
      match unit_char with
      | 'd' -> (String.sub s 0 (len - 1), 24 * 60 * 60)
      | 'h' -> (String.sub s 0 (len - 1), 60 * 60)
      | 'm' -> (String.sub s 0 (len - 1), 60)
      | 's' -> (String.sub s 0 (len - 1), 1)
      | '0' .. '9' -> (s, 1)
      | _ -> ("", 0)
    in
    let with_unit n factor =
      if n > max_int / factor then Error (`Msg "duration is too large")
      else Ok (n * factor)
    in
    if factor = 0 then Error (`Msg "duration unit must be one of s, m, h, or d")
    else
      match int_of_string_opt number with
      | None -> Error (`Msg "duration number must be an integer")
      | Some n when n < 0 -> Error (`Msg "duration must be non-negative")
      | Some n -> with_unit n factor

let duration_conv =
  let print ppf seconds = Format.fprintf ppf "%ds" seconds in
  Arg.conv (parse_duration, print)

let non_negative_int_conv name =
  let parse raw =
    match int_of_string_opt raw with
    | None -> Error (`Msg (Printf.sprintf "%s must be an integer" name))
    | Some n when n < 0 ->
        Error (`Msg (Printf.sprintf "%s must be non-negative" name))
    | Some n -> Ok n
  in
  let print = Format.pp_print_int in
  Arg.conv (parse, print)

let count_conv = non_negative_int_conv "count"
let threshold_conv = non_negative_int_conv "threshold"

let timezone_conv =
  let parse raw =
    Croncheck_lib.Timezone.parse raw |> Result.map_error (fun msg -> `Msg msg)
  in
  let print ppf timezone =
    Format.pp_print_string ppf (Croncheck_lib.Timezone.to_string timezone)
  in
  Arg.conv (parse, print)

let reject_json_time_format format time_format =
  match (format, time_format) with
  | Croncheck_lib.Output.Json, Croncheck_lib.Output.Human ->
      Error (`Msg "--time-format only applies to plain output")
  | _ -> Ok ()

let run_with_time_format format time_format f =
  match reject_json_time_format format time_format with
  | Error (`Msg msg) ->
      print_error msg
        ~hint:
          "Use --format plain with --time-format human, or omit --time-format \
           for JSON.";
      3
  | Ok () -> f ()

let ptime_conv =
  let parse s =
    match Ptime.of_rfc3339 s with
    | Ok (t, _, _) -> Ok t
    | Error _ -> (
        match String.split_on_char '-' s with
        | [ y; m; d ] -> (
            match
              (int_of_string_opt y, int_of_string_opt m, int_of_string_opt d)
            with
            | Some y, Some m, Some d -> (
                match Ptime.of_date_time ((y, m, d), ((0, 0, 0), 0)) with
                | Some t -> Ok t
                | None -> Error (`Msg (Printf.sprintf "invalid date %S" s)))
            | _ -> Error (`Msg (Printf.sprintf "invalid date %S" s)))
        | _ ->
            Error
              (`Msg
                 (Printf.sprintf
                    "expected RFC3339 timestamp or YYYY-MM-DD date, got %S" s)))
  in
  let print ppf t = Format.pp_print_string ppf (Ptime.to_rfc3339 t) in
  Arg.conv (parse, print)

let from_arg =
  Arg.(
    value
    & opt (some ptime_conv) None
    & info [ "from" ]
        ~doc:"Start time as RFC3339 or YYYY-MM-DD; defaults to now.")

let now () = Ptime_clock.now ()

let add_seconds t seconds =
  match Ptime.add_span t (Ptime.Span.of_int_s seconds) with
  | Some t -> t
  | None -> invalid_arg "time window out of range"

let exit_for_findings found = if found then 1 else 0

let all_finding_kinds =
  [
    Croncheck_lib.Check.Warnings;
    Croncheck_lib.Check.Conflicts;
    Croncheck_lib.Check.Overlaps;
    Croncheck_lib.Check.Policy;
  ]

let parse_fail_on_names names =
  let parse_one = function
    | "all" -> Ok all_finding_kinds
    | "none" -> Ok []
    | "warnings" -> Ok [ Croncheck_lib.Check.Warnings ]
    | "conflicts" -> Ok [ Croncheck_lib.Check.Conflicts ]
    | "overlaps" -> Ok [ Croncheck_lib.Check.Overlaps ]
    | "policy" -> Ok [ Croncheck_lib.Check.Policy ]
    | other ->
        Error
          (`Msg
             (Printf.sprintf
                "unknown finding category %S; expected all, none, warnings, \
                 conflicts, overlaps, or policy"
                other))
  in
  names
  |> List.fold_left
       (fun acc item ->
         match (acc, parse_one item) with
         | (Error _ as error), _ -> error
         | _, (Error _ as error) -> error
         | Ok acc, Ok kinds -> Ok (List.rev_append kinds acc))
       (Ok [])
  |> Result.map (List.sort_uniq compare)

let fail_on_conv =
  let parse raw =
    raw |> String.split_on_char ','
    |> List.map (fun s -> String.trim (String.lowercase_ascii s))
    |> List.filter (( <> ) "")
    |> parse_fail_on_names
  in
  let name = function
    | Croncheck_lib.Check.Warnings -> "warnings"
    | Croncheck_lib.Check.Conflicts -> "conflicts"
    | Croncheck_lib.Check.Overlaps -> "overlaps"
    | Croncheck_lib.Check.Policy -> "policy"
  in
  let print ppf kinds =
    if List.length kinds = List.length all_finding_kinds then
      Format.pp_print_string ppf "all"
    else Format.pp_print_string ppf (kinds |> List.map name |> String.concat ",")
  in
  Arg.conv (parse, print)

let read_stdin_lines () =
  let rec loop acc =
    match input_line stdin with
    | line -> loop (line :: acc)
    | exception End_of_file -> List.rev acc
  in
  loop []

let check_cmd =
  let effective_fail_on ~cli ~policy =
    match cli with
    | Some fail_on -> fail_on
    | None ->
        (match policy with
          | Some policy -> (
              match policy.Croncheck_lib.Policy.fail_on with
              | None -> None
              | Some names -> (
                  match parse_fail_on_names names with
                  | Ok fail_on -> Some fail_on
                  | Error _ -> None))
          | None -> None)
        |> Option.value ~default:all_finding_kinds
  in
  let run format time_format timezone window threshold duration policy_path
      fail_on_opt from_crontab system_crontab from_k8s from_opt =
    run_with_time_format format time_format (fun () ->
        let selected =
          List.filter_map Fun.id
            [
              Option.map (fun path -> `Crontab path) from_crontab;
              Option.map (fun path -> `K8s path) from_k8s;
            ]
        in
        if List.length selected > 1 then (
          print_error "choose only one input source"
            ~hint:
              "Use only one of --from-crontab or --from-k8s; omit both to read \
               from stdin.";
          3)
        else
          let source =
            match selected with
            | [] -> Croncheck_lib.Check.Stdin (read_stdin_lines ())
            | [ `Crontab path ] ->
                Croncheck_lib.Check.Crontab { path; system = system_crontab }
            | [ `K8s path ] -> Croncheck_lib.Check.Kubernetes path
            | _ -> Croncheck_lib.Check.Stdin []
          in
          match Croncheck_lib.Check.load source with
          | Error errors ->
              print_input_errors errors;
              2
          | Ok jobs -> (
              let from = Option.value from_opt ~default:(now ()) in
              let until = add_seconds from window in
              match policy_path with
              | None ->
                  let fail_on =
                    effective_fail_on ~cli:fail_on_opt ~policy:None
                  in
                  let report =
                    Croncheck_lib.Check.analyze ~timezone ~from ~until
                      ~threshold ~duration jobs
                  in
                  Croncheck_lib.Output.pp_check ~timezone Format.std_formatter
                    ~format ~time_format report;
                  exit_for_findings
                    (Croncheck_lib.Check.has_findings_for fail_on report)
              | Some path -> (
                  match Croncheck_lib.Policy.parse_config_file path with
                  | Error errors ->
                      print_input_errors errors;
                      2
                  | Ok policy_config ->
                      let fail_on =
                        effective_fail_on ~cli:fail_on_opt
                          ~policy:(Some policy_config)
                      in
                      let report =
                        Croncheck_lib.Check.analyze_with_policy ~timezone ~from
                          ~until ~threshold ~duration
                          ~policy:policy_config.rules jobs
                      in
                      Croncheck_lib.Output.pp_check_with_policy ~timezone
                        Format.std_formatter ~format ~time_format report;
                      exit_for_findings
                        (Croncheck_lib.Check.has_policy_findings_for fail_on
                           report))))
  in
  let term =
    Term.(
      const run
      $ Arg.(
          value
          & opt format_conv Croncheck_lib.Output.Plain
          & info [ "format" ] ~doc:"Output format: plain or json.")
      $ Arg.(
          value
          & opt time_format_conv Croncheck_lib.Output.Rfc3339
          & info [ "time-format" ]
              ~doc:"Plain timestamp format: rfc3339 or human.")
      $ Arg.(
          value
          & opt timezone_conv Croncheck_lib.Timezone.utc
          & info [ "tz" ]
              ~doc:
                "Default timezone: UTC, Z, fixed offset such as +02:00, or \
                 IANA name such as America/New_York.")
      $ Arg.(
          value
          & opt duration_conv (24 * 60 * 60)
          & info [ "window" ] ~doc:"Analysis window, e.g. 30d, 24h, 60m.")
      $ Arg.(
          value & opt threshold_conv 0
          & info [ "threshold" ] ~doc:"Conflict threshold in seconds.")
      $ Arg.(
          value
          & opt (some duration_conv) None
          & info [ "duration" ]
              ~doc:"Optional job duration for overlap analysis.")
      $ Arg.(
          value
          & opt (some string) None
          & info [ "policy" ]
              ~doc:"Read CI policy checks from a simple key-value file.")
      $ Arg.(
          value
          & opt (some fail_on_conv) None
          & info [ "fail-on" ]
              ~doc:
                "Comma-separated finding categories that should exit 1: all, \
                 none, warnings, conflicts, overlaps, policy.")
      $ Arg.(
          value
          & opt (some string) None
          & info [ "from-crontab" ] ~doc:"Read jobs from a crontab file.")
      $ Arg.(
          value & flag
          & info [ "system-crontab" ]
              ~doc:"Parse crontab as system format with a user column.")
      $ Arg.(
          value
          & opt (some string) None
          & info [ "from-k8s" ] ~doc:"Read jobs from Kubernetes CronJob YAML.")
      $ from_arg)
  in
  Cmd.v
    (Cmd.info "check"
       ~doc:"Analyze schedules from stdin, crontab, or Kubernetes YAML.")
    term

let load_cmd =
  let run format time_format timezone window bucket from_crontab system_crontab
      from_k8s from_opt =
    run_with_time_format format time_format (fun () ->
        let selected =
          List.filter_map Fun.id
            [
              Option.map (fun path -> `Crontab path) from_crontab;
              Option.map (fun path -> `K8s path) from_k8s;
            ]
        in
        if List.length selected > 1 then (
          print_error "choose only one input source"
            ~hint:
              "Use only one of --from-crontab or --from-k8s; omit both to read \
               from stdin.";
          3)
        else if bucket <= 0 then (
          print_error "--bucket must be greater than zero";
          3)
        else
          let source =
            match selected with
            | [] -> Croncheck_lib.Check.Stdin (read_stdin_lines ())
            | [ `Crontab path ] ->
                Croncheck_lib.Check.Crontab { path; system = system_crontab }
            | [ `K8s path ] -> Croncheck_lib.Check.Kubernetes path
            | _ -> Croncheck_lib.Check.Stdin []
          in
          match Croncheck_lib.Check.load source with
          | Error errors ->
              print_input_errors errors;
              2
          | Ok jobs ->
              let from = Option.value from_opt ~default:(now ()) in
              let until = add_seconds from window in
              let report =
                Croncheck_lib.Load.analyze ~timezone ~from ~until
                  ~bucket_seconds:bucket jobs
              in
              Croncheck_lib.Output.pp_load ~time_format Format.std_formatter
                ~format report;
              0)
  in
  let term =
    Term.(
      const run
      $ Arg.(
          value
          & opt format_conv Croncheck_lib.Output.Plain
          & info [ "format" ] ~doc:"Output format: plain or json.")
      $ Arg.(
          value
          & opt time_format_conv Croncheck_lib.Output.Rfc3339
          & info [ "time-format" ]
              ~doc:"Plain timestamp format: rfc3339 or human.")
      $ Arg.(
          value
          & opt timezone_conv Croncheck_lib.Timezone.utc
          & info [ "tz" ]
              ~doc:
                "Default timezone: UTC, Z, fixed offset such as +02:00, or \
                 IANA name such as America/New_York.")
      $ Arg.(
          value
          & opt duration_conv (24 * 60 * 60)
          & info [ "window" ] ~doc:"Analysis window, e.g. 30d, 24h, 60m.")
      $ Arg.(
          value
          & opt duration_conv (5 * 60)
          & info [ "bucket" ] ~doc:"Bucket size, e.g. 60m, 5m, or 1h.")
      $ Arg.(
          value
          & opt (some string) None
          & info [ "from-crontab" ] ~doc:"Read jobs from a crontab file.")
      $ Arg.(
          value & flag
          & info [ "system-crontab" ]
              ~doc:"Parse crontab as system format with a user column.")
      $ Arg.(
          value
          & opt (some string) None
          & info [ "from-k8s" ] ~doc:"Read jobs from Kubernetes CronJob YAML.")
      $ from_arg)
  in
  Cmd.v
    (Cmd.info "load" ~doc:"Summarize fleet schedule density by time bucket.")
    term

let until_arg =
  Arg.(
    value
    & opt (some ptime_conv) None
    & info [ "until" ]
        ~doc:"Stop at this time (RFC3339 or YYYY-MM-DD); defaults to no limit.")

let next_cmd =
  let run format time_format timezone count gaps from_opt until_opt raw =
    run_with_time_format format time_format (fun () ->
        match parse_expr raw with
        | Error (`Msg msg) ->
            print_parse_error ~expr:raw msg;
            2
        | Ok expr ->
            let from = Option.value from_opt ~default:(now ()) in
            let times =
              match until_opt with
              | None -> Croncheck_lib.Schedule.next_n ~timezone expr ~from count
              | Some until ->
                  let rec take n = function
                    | [] -> []
                    | _ when n = 0 -> []
                    | x :: rest -> x :: take (n - 1) rest
                  in
                  take count
                    (Croncheck_lib.Schedule.within ~timezone expr ~from ~until)
            in
            Croncheck_lib.Output.pp_next ~timezone ~gaps Format.std_formatter
              ~format ~time_format ~expr:raw times;
            0)
  in
  let term =
    Term.(
      const run
      $ Arg.(
          value
          & opt format_conv Croncheck_lib.Output.Plain
          & info [ "format" ] ~doc:"Output format: plain or json.")
      $ Arg.(
          value
          & opt time_format_conv Croncheck_lib.Output.Rfc3339
          & info [ "time-format" ]
              ~doc:"Plain timestamp format: rfc3339 or human.")
      $ Arg.(
          value
          & opt timezone_conv Croncheck_lib.Timezone.utc
          & info [ "tz" ]
              ~doc:
                "Timezone: UTC, Z, fixed offset such as +02:00, or IANA name \
                 such as America/New_York.")
      $ Arg.(
          value & opt count_conv 10
          & info [ "count"; "n" ] ~doc:"Number of fire times to print.")
      $ Arg.(
          value & flag
          & info [ "gaps" ] ~doc:"Show min/max/avg gap between fire times.")
      $ from_arg $ until_arg
      $ Arg.(required & pos 0 (some string) None & info [] ~docv:"EXPR"))
  in
  Cmd.v (Cmd.info "next" ~doc:"List next fire times.") term

let warn_cmd =
  let run format timezone raw =
    match parse_expr raw with
    | Error (`Msg msg) ->
        print_parse_error ~expr:raw msg;
        2
    | Ok expr ->
        let warnings = Croncheck_lib.Analysis.warn ~timezone expr in
        Croncheck_lib.Output.pp_warnings Format.std_formatter ~format ~expr:raw
          warnings;
        exit_for_findings (warnings <> [])
  in
  let term =
    Term.(
      const run
      $ Arg.(
          value
          & opt format_conv Croncheck_lib.Output.Plain
          & info [ "format" ] ~doc:"Output format: plain or json.")
      $ Arg.(
          value
          & opt timezone_conv Croncheck_lib.Timezone.utc
          & info [ "tz" ]
              ~doc:
                "Timezone: UTC, Z, fixed offset such as +02:00, or IANA name \
                 such as America/New_York.")
      $ Arg.(required & pos 0 (some string) None & info [] ~docv:"EXPR"))
  in
  Cmd.v (Cmd.info "warn" ~doc:"Report surprising cron semantics.") term

let conflicts_cmd =
  let run format time_format timezone window threshold from_opt raw_a raw_b =
    run_with_time_format format time_format (fun () ->
        match (parse_expr raw_a, parse_expr raw_b) with
        | Error (`Msg msg), _ ->
            print_parse_error ~expr:raw_a msg;
            2
        | _, Error (`Msg msg) ->
            print_parse_error ~expr:raw_b msg;
            2
        | Ok expr_a, Ok expr_b ->
            let from = Option.value from_opt ~default:(now ()) in
            let until = add_seconds from window in
            let conflicts =
              Croncheck_lib.Analysis.conflicts_with_timezone ~timezone ~expr_a
                ~expr_b ~from ~until ~threshold
              |> List.map (fun c ->
                  {
                    c with
                    Croncheck_lib.Analysis.expr_a = raw_a;
                    expr_b = raw_b;
                  })
            in
            Croncheck_lib.Output.pp_conflicts ~timezone Format.std_formatter
              ~format ~time_format conflicts;
            exit_for_findings (conflicts <> []))
  in
  let term =
    Term.(
      const run
      $ Arg.(
          value
          & opt format_conv Croncheck_lib.Output.Plain
          & info [ "format" ] ~doc:"Output format: plain or json.")
      $ Arg.(
          value
          & opt time_format_conv Croncheck_lib.Output.Rfc3339
          & info [ "time-format" ]
              ~doc:"Plain timestamp format: rfc3339 or human.")
      $ Arg.(
          value
          & opt timezone_conv Croncheck_lib.Timezone.utc
          & info [ "tz" ]
              ~doc:
                "Timezone: UTC, Z, fixed offset such as +02:00, or IANA name \
                 such as America/New_York.")
      $ Arg.(
          value
          & opt duration_conv (24 * 60 * 60)
          & info [ "window" ] ~doc:"Search window, e.g. 30d, 24h, 60m.")
      $ Arg.(
          value & opt threshold_conv 0
          & info [ "threshold" ] ~doc:"Conflict threshold in seconds.")
      $ from_arg
      $ Arg.(required & pos 0 (some string) None & info [] ~docv:"EXPR")
      $ Arg.(required & pos 1 (some string) None & info [] ~docv:"EXPR"))
  in
  Cmd.v
    (Cmd.info "conflicts" ~doc:"Find nearby fire times between two expressions.")
    term

let overlaps_cmd =
  let run format time_format timezone window duration from_opt raw =
    run_with_time_format format time_format (fun () ->
        match parse_expr raw with
        | Error (`Msg msg) ->
            print_parse_error ~expr:raw msg;
            2
        | Ok expr ->
            let from = Option.value from_opt ~default:(now ()) in
            let until = add_seconds from window in
            let overlaps =
              Croncheck_lib.Analysis.overlaps ~timezone expr ~from ~until
                ~duration
            in
            Croncheck_lib.Output.pp_overlaps ~timezone Format.std_formatter
              ~format ~time_format overlaps;
            exit_for_findings (overlaps <> []))
  in
  let term =
    Term.(
      const run
      $ Arg.(
          value
          & opt format_conv Croncheck_lib.Output.Plain
          & info [ "format" ] ~doc:"Output format: plain or json.")
      $ Arg.(
          value
          & opt time_format_conv Croncheck_lib.Output.Rfc3339
          & info [ "time-format" ]
              ~doc:"Plain timestamp format: rfc3339 or human.")
      $ Arg.(
          value
          & opt timezone_conv Croncheck_lib.Timezone.utc
          & info [ "tz" ]
              ~doc:
                "Timezone: UTC, Z, fixed offset such as +02:00, or IANA name \
                 such as America/New_York.")
      $ Arg.(
          value
          & opt duration_conv (24 * 60 * 60)
          & info [ "window" ] ~doc:"Search window, e.g. 30d, 24h, 60m.")
      $ Arg.(
          value & opt duration_conv 60
          & info [ "duration" ] ~doc:"Assumed job duration, e.g. 30s or 5m.")
      $ from_arg
      $ Arg.(required & pos 0 (some string) None & info [] ~docv:"EXPR"))
  in
  Cmd.v
    (Cmd.info "overlaps" ~doc:"Find self-overlaps for a long-running job.")
    term

let diff_cmd =
  let run format time_format timezone window from_opt raw_a raw_b =
    run_with_time_format format time_format (fun () ->
        match (parse_expr raw_a, parse_expr raw_b) with
        | Error (`Msg msg), _ ->
            print_parse_error ~expr:raw_a msg;
            2
        | _, Error (`Msg msg) ->
            print_parse_error ~expr:raw_b msg;
            2
        | Ok expr_a, Ok expr_b ->
            let from = Option.value from_opt ~default:(now ()) in
            let until = add_seconds from window in
            let entries =
              Croncheck_lib.Analysis.diff ~timezone expr_a ~expr_b ~from ~until
            in
            Croncheck_lib.Output.pp_diff ~timezone ~time_format
              Format.std_formatter ~format ~expr_a:raw_a ~expr_b:raw_b entries;
            let differs =
              List.exists
                (fun e ->
                  e.Croncheck_lib.Analysis.side <> Croncheck_lib.Analysis.Both)
                entries
            in
            exit_for_findings differs)
  in
  let term =
    Term.(
      const run
      $ Arg.(
          value
          & opt format_conv Croncheck_lib.Output.Plain
          & info [ "format" ] ~doc:"Output format: plain or json.")
      $ Arg.(
          value
          & opt time_format_conv Croncheck_lib.Output.Rfc3339
          & info [ "time-format" ]
              ~doc:"Plain timestamp format: rfc3339 or human.")
      $ Arg.(
          value
          & opt timezone_conv Croncheck_lib.Timezone.utc
          & info [ "tz" ]
              ~doc:
                "Timezone: UTC, Z, fixed offset such as +02:00, or IANA name \
                 such as America/New_York.")
      $ Arg.(
          value
          & opt duration_conv (24 * 60 * 60)
          & info [ "window" ] ~doc:"Comparison window, e.g. 30d, 24h, 60m.")
      $ from_arg
      $ Arg.(required & pos 0 (some string) None & info [] ~docv:"EXPR")
      $ Arg.(required & pos 1 (some string) None & info [] ~docv:"EXPR"))
  in
  Cmd.v (Cmd.info "diff" ~doc:"Compare fire times of two expressions.") term

let explain_cmd =
  let run format raw =
    match parse_expr raw with
    | Error (`Msg msg) ->
        print_parse_error ~expr:raw msg;
        2
    | Ok expr ->
        let description = Croncheck_lib.Explain.describe expr in
        Croncheck_lib.Output.pp_explain Format.std_formatter ~format ~expr:raw
          description;
        0
  in
  let term =
    Term.(
      const run
      $ Arg.(
          value
          & opt format_conv Croncheck_lib.Output.Plain
          & info [ "format" ] ~doc:"Output format: plain or json.")
      $ Arg.(required & pos 0 (some string) None & info [] ~docv:"EXPR"))
  in
  Cmd.v
    (Cmd.info "explain" ~doc:"Describe a cron expression in plain English.")
    term

let doctor_cmd =
  let run timezone_name =
    let root_status root =
      let available =
        try Sys.file_exists root && Sys.is_directory root
        with Sys_error _ -> false
      in
      Printf.sprintf "  - %s: %s" root
        (if available then "available" else "missing")
    in
    let parsed = Croncheck_lib.Timezone.parse timezone_name in
    Format.printf "croncheck doctor@.";
    Format.printf "version: %s@." Croncheck_lib.Version.current;
    Format.printf "os: %s@." Sys.os_type;
    Format.printf "zoneinfo roots:@.";
    List.iter
      (fun root -> Format.printf "%s@." (root_status root))
      Croncheck_lib.Timezone.zoneinfo_roots;
    Format.printf "timezone probe: %s@." timezone_name;
    (match parsed with
    | Ok timezone -> (
        let kind =
          match timezone with
          | Croncheck_lib.Timezone.Utc -> "utc"
          | Croncheck_lib.Timezone.Fixed_offset _ -> "fixed-offset"
          | Croncheck_lib.Timezone.Iana _ -> "iana"
        in
        Format.printf "timezone status: ok (%s)@." kind;
        Format.printf "timezone normalized: %s@."
          (Croncheck_lib.Timezone.to_string timezone);
        let zoneinfo_path =
          match timezone with
          | Croncheck_lib.Timezone.Iana _ ->
              Croncheck_lib.Timezone.zoneinfo_path timezone_name
          | Croncheck_lib.Timezone.Utc | Croncheck_lib.Timezone.Fixed_offset _
            ->
              None
        in
        match zoneinfo_path with
        | Some path -> Format.printf "zoneinfo file: %s@." path
        | None -> Format.printf "zoneinfo file: n/a@.")
    | Error message ->
        Format.printf "timezone status: unavailable@.";
        Format.printf "timezone error: %s@." message;
        Format.printf
          "hint: install tzdata or use a runtime image that includes \
           /usr/share/zoneinfo for IANA timezone support@.");
    0
  in
  let term =
    Term.(
      const run
      $ Arg.(
          value
          & opt string "America/New_York"
          & info [ "tz" ]
              ~doc:
                "Timezone probe for diagnostics; defaults to America/New_York."))
  in
  Cmd.v
    (Cmd.info "doctor"
       ~doc:"Print runtime diagnostics for timezone and container setup.")
    term

let () =
  let info =
    Cmd.info "croncheck"
      ~doc:"Static analysis for POSIX and basic Quartz cron expressions."
  in
  let cmd =
    Cmd.group info
      [
        next_cmd;
        warn_cmd;
        conflicts_cmd;
        overlaps_cmd;
        diff_cmd;
        load_cmd;
        check_cmd;
        explain_cmd;
        doctor_cmd;
      ]
  in
  let code =
    match Cmd.eval_value cmd with
    | Ok (`Ok code) -> code
    | Ok `Help | Ok `Version -> 0
    | Error (`Parse | `Term) -> 3
    | Error `Exn -> 3
  in
  exit code
