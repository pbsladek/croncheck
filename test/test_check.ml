open Croncheck_lib

let time y m d h min =
  Option.get (Ptime.of_date_time ((y, m, d), ((h, min, 0), 0)))

let job_of_expr s =
  match Check.load (Check.Stdin [ s ]) with
  | Ok [ j ] -> j
  | Ok _ -> invalid_arg "expected one job"
  | Error _ -> invalid_arg s

let write_temp content =
  let path = Filename.temp_file "croncheck_test" ".txt" in
  let oc = open_out path in
  output_string oc content;
  close_out oc;
  path

(* load via Stdin (exercises parse_stdin) *)

let test_load_stdin_two_jobs () =
  match Check.load (Check.Stdin [ "0 0 * * *"; "0 0 31 * *" ]) with
  | Ok jobs -> Alcotest.(check int) "two jobs" 2 (List.length jobs)
  | Error _ -> Alcotest.fail "expected success"

let test_load_stdin_skips_blank_and_comments () =
  match Check.load (Check.Stdin [ ""; "# comment"; "  "; "0 0 * * *" ]) with
  | Ok [ job ] -> Alcotest.(check string) "expr" "0 0 * * *" job.Job.expr_raw
  | Ok jobs -> Alcotest.failf "expected one job, got %d" (List.length jobs)
  | Error _ -> Alcotest.fail "expected success"

let test_load_stdin_parse_error () =
  match Check.load (Check.Stdin [ "60 * * * *" ]) with
  | Error [ msg ] ->
      Alcotest.(check bool)
        "has stdin prefix" true
        (String.length msg > 5 && String.sub msg 0 5 = "stdin")
  | Error msgs -> Alcotest.failf "expected one error, got %d" (List.length msgs)
  | Ok _ -> Alcotest.fail "expected parse error"

(* load via Crontab *)

let test_load_crontab_missing_file () =
  match
    Check.load (Check.Crontab { path = "/no/such/file"; system = false })
  with
  | Error [ msg ] ->
      Alcotest.(check bool) "mentions path" true (String.contains msg '/')
  | Error msgs -> Alcotest.failf "expected one error, got %d" (List.length msgs)
  | Ok _ -> Alcotest.fail "expected error"

let test_load_crontab_error_with_line () =
  let path = write_temp "60 * * * * /bin/job\n" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      match Check.load (Check.Crontab { path; system = false }) with
      | Error [ msg ] ->
          Alcotest.(check bool)
            "mentions line number" true (String.contains msg ':')
      | Error msgs ->
          Alcotest.failf "expected one error, got %d" (List.length msgs)
      | Ok _ -> Alcotest.fail "expected error")

(* load via Kubernetes *)

let test_load_kubernetes_missing_file () =
  match Check.load (Check.Kubernetes "/no/such/file.yaml") with
  | Error [ msg ] ->
      Alcotest.(check bool) "mentions path" true (String.contains msg '/')
  | Error msgs -> Alcotest.failf "expected one error, got %d" (List.length msgs)
  | Ok _ -> Alcotest.fail "expected error"

let test_load_kubernetes_error_with_line () =
  let path =
    write_temp
      {|apiVersion: batch/v1
kind: CronJob
metadata:
  name: bad
spec:
  schedule: "60 * * * *"
|}
  in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      match Check.load (Check.Kubernetes path) with
      | Error [ msg ] ->
          Alcotest.(check bool)
            "mentions line number" true (String.contains msg ':')
      | Error msgs ->
          Alcotest.failf "expected one error, got %d" (List.length msgs)
      | Ok _ -> Alcotest.fail "expected error")

(* analyze *)

let test_analyze_no_conflicts () =
  let jobs = [ job_of_expr "0 0 * * *" ] in
  let from = time 2024 1 1 0 0 in
  let until = time 2024 1 1 1 0 in
  let report =
    Check.analyze ~timezone:Timezone.utc ~from ~until ~threshold:0
      ~duration:None jobs
  in
  Alcotest.(check int) "one job" 1 (List.length report.Check.jobs);
  Alcotest.(check int) "no conflicts" 0 (List.length report.conflicts)

let test_analyze_with_conflicts () =
  let jobs = [ job_of_expr "*/5 * * * *"; job_of_expr "*/15 * * * *" ] in
  let from = time 2024 1 1 0 0 in
  let until = time 2024 1 1 1 0 in
  let report =
    Check.analyze ~timezone:Timezone.utc ~from ~until ~threshold:0
      ~duration:None jobs
  in
  Alcotest.(check bool) "has conflicts" true (report.conflicts <> [])

let test_analyze_with_overlaps () =
  let jobs = [ job_of_expr "* * * * *" ] in
  let from = time 2024 1 1 0 0 in
  let until = time 2024 1 1 0 10 in
  let report =
    Check.analyze ~timezone:Timezone.utc ~from ~until ~threshold:0
      ~duration:(Some 120) jobs
  in
  Alcotest.(check bool) "has overlaps" true (report.overlaps <> [])

(* has_findings *)

let test_has_findings_with_warnings () =
  let jobs = [ job_of_expr "0 0 31 * *" ] in
  let from = time 2024 1 1 0 0 in
  let until = time 2024 2 1 0 0 in
  let report =
    Check.analyze ~timezone:Timezone.utc ~from ~until ~threshold:0
      ~duration:None jobs
  in
  Alcotest.(check bool) "has findings" true (Check.has_findings report)

let test_has_findings_clean () =
  let jobs = [ job_of_expr "0 0 * * *" ] in
  let from = time 2024 1 1 0 0 in
  let until = time 2024 2 1 0 0 in
  let report =
    Check.analyze ~timezone:Timezone.utc ~from ~until ~threshold:0
      ~duration:None jobs
  in
  Alcotest.(check bool) "no findings" false (Check.has_findings report)

let () =
  Alcotest.run "check"
    [
      ( "load-stdin",
        [
          Alcotest.test_case "two jobs" `Quick test_load_stdin_two_jobs;
          Alcotest.test_case "skips blank and comments" `Quick
            test_load_stdin_skips_blank_and_comments;
          Alcotest.test_case "parse error" `Quick test_load_stdin_parse_error;
        ] );
      ( "load-crontab",
        [
          Alcotest.test_case "missing file" `Quick
            test_load_crontab_missing_file;
          Alcotest.test_case "error with line" `Quick
            test_load_crontab_error_with_line;
        ] );
      ( "load-kubernetes",
        [
          Alcotest.test_case "missing file" `Quick
            test_load_kubernetes_missing_file;
          Alcotest.test_case "error with line" `Quick
            test_load_kubernetes_error_with_line;
        ] );
      ( "analyze",
        [
          Alcotest.test_case "no conflicts" `Quick test_analyze_no_conflicts;
          Alcotest.test_case "with conflicts" `Quick test_analyze_with_conflicts;
          Alcotest.test_case "with overlaps" `Quick test_analyze_with_overlaps;
        ] );
      ( "has-findings",
        [
          Alcotest.test_case "with warnings" `Quick
            test_has_findings_with_warnings;
          Alcotest.test_case "clean" `Quick test_has_findings_clean;
        ] );
    ]
