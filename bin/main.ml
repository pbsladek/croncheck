open Cmdliner

let parse_expr raw =
  match Croncheck_lib.Cron.parse raw with
  | Ok expr -> Ok expr
  | Error e -> Error (`Msg (Croncheck_lib.Cron.parse_error_to_string e))

let print_error ?hint message =
  Printf.eprintf "Error: %s\n" message;
  Option.iter (Printf.eprintf "Hint: %s\n") hint

let print_parse_error ~expr reason =
  Printf.eprintf "Error: invalid cron expression\n";
  Printf.eprintf "  expression: %s\n" expr;
  Printf.eprintf "  reason: %s\n" reason

let print_input_errors errors =
  Printf.eprintf "Error: failed to parse input\n";
  List.iter (Printf.eprintf "  - %s\n") errors

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
  if len < 2 then Error (`Msg "expected duration like 30d, 24h, or 60m")
  else
    let unit_char = s.[len - 1] in
    let number = String.sub s 0 (len - 1) in
    let with_unit n factor =
      if n > max_int / factor then Error (`Msg "duration is too large")
      else Ok (n * factor)
    in
    match int_of_string_opt number with
    | None -> Error (`Msg "duration number must be an integer")
    | Some n when n < 0 -> Error (`Msg "duration must be non-negative")
    | Some n -> (
        match unit_char with
        | 'd' -> with_unit n (24 * 60 * 60)
        | 'h' -> with_unit n (60 * 60)
        | 'm' -> with_unit n 60
        | _ -> Error (`Msg "duration unit must be one of d, h, or m"))

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
let seconds_duration_conv = non_negative_int_conv "duration"

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

let now () = Ptime_clock.now ()

let add_seconds t seconds =
  match Ptime.add_span t (Ptime.Span.of_int_s seconds) with
  | Some t -> t
  | None -> invalid_arg "time window out of range"

let exit_for_findings found = if found then 1 else 0

let read_stdin_lines () =
  let rec loop acc =
    match input_line stdin with
    | line -> loop (line :: acc)
    | exception End_of_file -> List.rev acc
  in
  loop []

let check_cmd =
  let run format time_format timezone window threshold duration from_crontab
      system_crontab from_k8s =
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
          | Ok jobs ->
              let from = now () in
              let until = add_seconds from window in
              let report =
                Croncheck_lib.Check.analyze ~timezone ~from ~until ~threshold
                  ~duration jobs
              in
              Croncheck_lib.Output.pp_check ~timezone Format.std_formatter
                ~format ~time_format report;
              exit_for_findings (Croncheck_lib.Check.has_findings report))
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
          & info [ "from-crontab" ] ~doc:"Read jobs from a crontab file.")
      $ Arg.(
          value & flag
          & info [ "system-crontab" ]
              ~doc:"Parse crontab as system format with a user column.")
      $ Arg.(
          value
          & opt (some string) None
          & info [ "from-k8s" ] ~doc:"Read jobs from Kubernetes CronJob YAML."))
  in
  Cmd.v
    (Cmd.info "check"
       ~doc:"Analyze schedules from stdin, crontab, or Kubernetes YAML.")
    term

let next_cmd =
  let run format time_format timezone count raw =
    run_with_time_format format time_format (fun () ->
        match parse_expr raw with
        | Error (`Msg msg) ->
            print_parse_error ~expr:raw msg;
            2
        | Ok expr ->
            let times =
              Croncheck_lib.Schedule.next_n ~timezone expr ~from:(now ()) count
            in
            Croncheck_lib.Output.pp_next ~timezone Format.std_formatter ~format
              ~time_format ~expr:raw times;
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
  let run format time_format timezone window threshold raw_a raw_b =
    run_with_time_format format time_format (fun () ->
        match (parse_expr raw_a, parse_expr raw_b) with
        | Error (`Msg msg), _ ->
            print_parse_error ~expr:raw_a msg;
            2
        | _, Error (`Msg msg) ->
            print_parse_error ~expr:raw_b msg;
            2
        | Ok expr_a, Ok expr_b ->
            let from = now () in
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
      $ Arg.(required & pos 0 (some string) None & info [] ~docv:"EXPR")
      $ Arg.(required & pos 1 (some string) None & info [] ~docv:"EXPR"))
  in
  Cmd.v
    (Cmd.info "conflicts" ~doc:"Find nearby fire times between two expressions.")
    term

let overlaps_cmd =
  let run format time_format timezone window duration raw =
    run_with_time_format format time_format (fun () ->
        match parse_expr raw with
        | Error (`Msg msg) ->
            print_parse_error ~expr:raw msg;
            2
        | Ok expr ->
            let from = now () in
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
          value
          & opt seconds_duration_conv 60
          & info [ "duration" ] ~doc:"Assumed job duration in seconds.")
      $ Arg.(required & pos 0 (some string) None & info [] ~docv:"EXPR"))
  in
  Cmd.v
    (Cmd.info "overlaps" ~doc:"Find self-overlaps for a long-running job.")
    term

let () =
  let info =
    Cmd.info "croncheck"
      ~doc:"Static analysis for POSIX and basic Quartz cron expressions."
  in
  let cmd =
    Cmd.group info
      [ next_cmd; warn_cmd; conflicts_cmd; overlaps_cmd; check_cmd ]
  in
  let code =
    match Cmd.eval_value cmd with
    | Ok (`Ok code) -> code
    | Ok `Help | Ok `Version -> 0
    | Error (`Parse | `Term) -> 3
    | Error `Exn -> 3
  in
  exit code
