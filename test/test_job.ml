open Croncheck_lib

let make_job ?id ?command ?line ?timezone source expr_raw =
  match Job.make ?id ?command ?line ?timezone ~source expr_raw with
  | Ok job -> job
  | Error _ -> invalid_arg expr_raw

let test_label_id_and_line () =
  let job =
    make_job ~id:"backup" ~line:3 (Job.CrontabFile "/etc/crontab") "0 0 * * *"
  in
  Alcotest.(check string) "label" "/etc/crontab:3 backup" (Job.label job)

let test_label_id_only () =
  let job = make_job ~id:"backup" Job.Cli "0 0 * * *" in
  Alcotest.(check string) "label" "backup" (Job.label job)

let test_label_line_only () =
  let job = make_job ~line:2 Job.Stdin "0 0 * * *" in
  Alcotest.(check string) "label" "stdin:2" (Job.label job)

let test_label_expr_fallback () =
  let job = make_job Job.Cli "0 0 * * *" in
  Alcotest.(check string) "label" "0 0 * * *" (Job.label job)

let test_source_to_string_cli () =
  let job = make_job Job.Cli "0 0 * * *" in
  Alcotest.(check string) "source" "cli" (Job.source_to_string job.source)

let test_source_to_string_stdin () =
  let job = make_job Job.Stdin "0 0 * * *" in
  Alcotest.(check string) "source" "stdin" (Job.source_to_string job.source)

let test_source_to_string_crontab () =
  let job = make_job (Job.CrontabFile "/etc/crontab") "0 0 * * *" in
  Alcotest.(check string)
    "source" "/etc/crontab"
    (Job.source_to_string job.source)

let test_source_to_string_kubernetes () =
  let job = make_job (Job.KubernetesYaml "jobs.yaml") "0 0 * * *" in
  Alcotest.(check string) "source" "jobs.yaml" (Job.source_to_string job.source)

let test_make_error () =
  Alcotest.(check bool)
    "parse error" true
    (Result.is_error (Job.make ~source:Job.Cli "60 * * * *"))

let () =
  Alcotest.run "job"
    [
      ( "label",
        [
          Alcotest.test_case "id and line" `Quick test_label_id_and_line;
          Alcotest.test_case "id only" `Quick test_label_id_only;
          Alcotest.test_case "line only" `Quick test_label_line_only;
          Alcotest.test_case "expr fallback" `Quick test_label_expr_fallback;
        ] );
      ( "source-to-string",
        [
          Alcotest.test_case "cli" `Quick test_source_to_string_cli;
          Alcotest.test_case "stdin" `Quick test_source_to_string_stdin;
          Alcotest.test_case "crontab" `Quick test_source_to_string_crontab;
          Alcotest.test_case "kubernetes" `Quick
            test_source_to_string_kubernetes;
        ] );
      ("make", [ Alcotest.test_case "error" `Quick test_make_error ]);
    ]
