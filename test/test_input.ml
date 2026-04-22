open Croncheck_lib

let test_crontab_user () =
  let lines =
    [
      "SHELL=/bin/sh";
      "MAILTO = ops@example.com";
      "CRON_TZ=UTC";
      "# comment";
      "*/5\t*\t*\t*\t*\t/usr/bin/job --flag";
    ]
  in
  match Crontab.parse_lines ~source_path:"crontab" lines with
  | Error errors ->
      Alcotest.failf "unexpected crontab errors: %d" (List.length errors)
  | Ok [ job ] ->
      Alcotest.(check string) "expr" "*/5 * * * *" job.Job.expr_raw;
      Alcotest.(check (option string))
        "command" (Some "/usr/bin/job --flag") job.command;
      Alcotest.(check (option int)) "line" (Some 5) job.line
  | Ok jobs -> Alcotest.failf "expected one job, got %d" (List.length jobs)

let test_crontab_system () =
  let lines = [ "0 0 * * * root /usr/bin/backup" ] in
  match Crontab.parse_lines ~system:true ~source_path:"/etc/crontab" lines with
  | Ok [ job ] ->
      Alcotest.(check (option string)) "user id" (Some "root") job.id;
      Alcotest.(check (option string))
        "command" (Some "/usr/bin/backup") job.command
  | Error errors ->
      Alcotest.failf "unexpected crontab errors: %d" (List.length errors)
  | Ok jobs -> Alcotest.failf "expected one job, got %d" (List.length jobs)

let test_crontab_macro () =
  let lines = [ "@daily /usr/bin/daily-job" ] in
  match Crontab.parse_lines ~source_path:"crontab" lines with
  | Ok [ job ] ->
      Alcotest.(check string) "expanded macro" "0 0 * * *" job.expr_raw;
      Alcotest.(check (option string))
        "command" (Some "/usr/bin/daily-job") job.command
  | Error errors ->
      Alcotest.failf "unexpected crontab errors: %d" (List.length errors)
  | Ok jobs -> Alcotest.failf "expected one job, got %d" (List.length jobs)

let test_system_crontab_macro () =
  let lines = [ "@hourly root /usr/bin/hourly-job" ] in
  match Crontab.parse_lines ~system:true ~source_path:"/etc/crontab" lines with
  | Ok [ job ] ->
      Alcotest.(check string) "expanded macro" "0 * * * *" job.expr_raw;
      Alcotest.(check (option string)) "user id" (Some "root") job.id;
      Alcotest.(check (option string))
        "command" (Some "/usr/bin/hourly-job") job.command
  | Error errors ->
      Alcotest.failf "unexpected crontab errors: %d" (List.length errors)
  | Ok jobs -> Alcotest.failf "expected one job, got %d" (List.length jobs)

let test_crontab_reboot_rejected () =
  let lines = [ "@reboot /usr/bin/startup" ] in
  match Crontab.parse_lines ~source_path:"crontab" lines with
  | Error [ error ] ->
      Alcotest.(check (option int)) "line" (Some 1) error.Crontab.line
  | Error errors ->
      Alcotest.failf "expected one error, got %d" (List.length errors)
  | Ok _ -> Alcotest.fail "expected @reboot to be rejected"

let test_crontab_missing_file () =
  match Crontab.parse_file "/definitely/not/a/real/crontab" with
  | Error [ error ] ->
      Alcotest.(check (option int)) "line" None error.Crontab.line;
      Alcotest.(check bool)
        "message mentions path" true
        (String.contains error.message '/')
  | Error errors ->
      Alcotest.failf "expected one error, got %d" (List.length errors)
  | Ok _ -> Alcotest.fail "expected missing file to fail"

let test_kubernetes_yaml () =
  let lines =
    [
      "apiVersion: batch/v1";
      "kind: CronJob";
      "metadata:";
      "  name: cleanup";
      "  namespace: ops";
      "spec:";
      "  schedule: \"0 0 * * *\"";
      "  timeZone: \"+02:00\"";
      "---";
      "kind: ConfigMap";
      "metadata:";
      "  name: ignored";
    ]
  in
  match Kubernetes.parse_lines ~source_path:"jobs.yaml" lines with
  | Ok [ job ] ->
      Alcotest.(check (option string)) "id" (Some "ops/cleanup") job.id;
      Alcotest.(check string) "schedule" "0 0 * * *" job.expr_raw;
      Alcotest.(check (option string))
        "timezone" (Some "+02:00")
        (Option.map Timezone.to_string job.timezone)
  | Error errors ->
      Alcotest.failf "unexpected k8s errors: %d" (List.length errors)
  | Ok jobs -> Alcotest.failf "expected one job, got %d" (List.length jobs)

let test_kubernetes_missing_file () =
  let path = "/definitely/not/a/real/cronjob.yaml" in
  match Kubernetes.parse_file path with
  | Error [ error ] ->
      Alcotest.(check string) "file" path error.Kubernetes.file;
      Alcotest.(check (option int)) "line" None error.line
  | Error errors ->
      Alcotest.failf "expected one error, got %d" (List.length errors)
  | Ok _ -> Alcotest.fail "expected missing file to fail"

let () =
  Alcotest.run "input"
    [
      ( "crontab",
        [
          Alcotest.test_case "user" `Quick test_crontab_user;
          Alcotest.test_case "system" `Quick test_crontab_system;
          Alcotest.test_case "macro" `Quick test_crontab_macro;
          Alcotest.test_case "system macro" `Quick test_system_crontab_macro;
          Alcotest.test_case "reboot rejected" `Quick
            test_crontab_reboot_rejected;
          Alcotest.test_case "missing file" `Quick test_crontab_missing_file;
        ] );
      ( "kubernetes",
        [
          Alcotest.test_case "cronjob yaml" `Quick test_kubernetes_yaml;
          Alcotest.test_case "missing file" `Quick test_kubernetes_missing_file;
        ] );
    ]
