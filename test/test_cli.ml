let exe =
  if Sys.file_exists "_build/default/bin/main.exe" then
    "_build/default/bin/main.exe"
  else "../bin/main.exe"

let run args =
  let command = String.concat " " (List.map Filename.quote (exe :: args)) in
  Sys.command command

let write_temp content =
  let path = Filename.temp_file "croncheck_cli" ".txt" in
  let oc = open_out path in
  output_string oc content;
  close_out oc;
  path

let test_warn_clean_exit () =
  Alcotest.(check int) "exit code" 0 (run [ "warn"; "0 0 * * *" ])

let test_warn_finding_exit () =
  Alcotest.(check int) "exit code" 1 (run [ "warn"; "0 0 31 * *" ])

let test_parse_error_exit () =
  Alcotest.(check int) "exit code" 2 (run [ "warn"; "60 * * * *" ])

let test_usage_error_exit () =
  Alcotest.(check int)
    "exit code" 3
    (run [ "next"; "0 0 * * *"; "--tz"; "No/Such_Zone" ])

let test_macro_cli () =
  Alcotest.(check int) "exit code" 0 (run [ "next"; "@daily"; "--count"; "1" ])

let test_doctor_cli () =
  Alcotest.(check int) "exit code" 0 (run [ "doctor"; "--tz"; "UTC" ])

let test_check_fail_on_none () =
  let path = write_temp "0 0 31 * * /bin/job\n" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      Alcotest.(check int)
        "exit code" 0
        (run [ "check"; "--from-crontab"; path; "--fail-on"; "none" ]))

let test_check_fail_on_warnings () =
  let path = write_temp "0 0 31 * * /bin/job\n" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      Alcotest.(check int)
        "exit code" 1
        (run [ "check"; "--from-crontab"; path; "--fail-on"; "warnings" ]))

let test_check_fail_on_invalid_category () =
  Alcotest.(check int) "exit code" 3 (run [ "check"; "--fail-on"; "lint" ])

let test_check_policy_file_fail_on_none () =
  let cron = write_temp "0 0 31 * * /bin/job\n" in
  let policy = write_temp "fail_on: none\n" in
  Fun.protect
    ~finally:(fun () ->
      Sys.remove cron;
      Sys.remove policy)
    (fun () ->
      Alcotest.(check int)
        "exit code" 0
        (run [ "check"; "--from-crontab"; cron; "--policy"; policy ]))

let test_overlaps_duration_with_unit () =
  Alcotest.(check int)
    "exit code" 1
    (run [ "overlaps"; "* * * * *"; "--window"; "5m"; "--duration"; "120s" ])

let () =
  Alcotest.run "cli"
    [
      ( "exit-codes",
        [
          Alcotest.test_case "warn clean" `Quick test_warn_clean_exit;
          Alcotest.test_case "warn finding" `Quick test_warn_finding_exit;
          Alcotest.test_case "parse error" `Quick test_parse_error_exit;
          Alcotest.test_case "usage error" `Quick test_usage_error_exit;
          Alcotest.test_case "macro" `Quick test_macro_cli;
          Alcotest.test_case "doctor" `Quick test_doctor_cli;
          Alcotest.test_case "check fail-on none" `Quick test_check_fail_on_none;
          Alcotest.test_case "check fail-on warnings" `Quick
            test_check_fail_on_warnings;
          Alcotest.test_case "check fail-on invalid category" `Quick
            test_check_fail_on_invalid_category;
          Alcotest.test_case "check policy fail-on none" `Quick
            test_check_policy_file_fail_on_none;
          Alcotest.test_case "overlaps duration with unit" `Quick
            test_overlaps_duration_with_unit;
        ] );
    ]
