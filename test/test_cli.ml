let exe =
  if Sys.file_exists "_build/default/bin/main.exe" then
    "_build/default/bin/main.exe"
  else "../bin/main.exe"

let run args =
  let command = String.concat " " (List.map Filename.quote (exe :: args)) in
  Sys.command command

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
        ] );
    ]
