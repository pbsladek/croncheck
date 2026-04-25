open Croncheck_lib

let time y m d h min =
  Option.get (Ptime.of_date_time ((y, m, d), ((h, min, 0), 0)))

let job ?timezone s =
  match Job.make ?timezone ~source:Job.Stdin s with
  | Ok job -> job
  | Error e -> Alcotest.fail (Cron.parse_error_to_string e)

let write_temp content =
  let path = Filename.temp_file "croncheck_policy" ".txt" in
  let oc = open_out path in
  output_string oc content;
  close_out oc;
  path

let test_parse_policy_file () =
  let path =
    write_temp
      {|
forbid_every_minute: true
require_timezone: false
max_frequency_per_hour: 12
disallow_midnight_utc: true
|}
  in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      match Policy.parse_file path with
      | Ok rules -> Alcotest.(check int) "rules" 3 (List.length rules)
      | Error errors -> Alcotest.fail (String.concat "; " errors))

let test_parse_policy_error () =
  let path = write_temp "max_frequency_per_hour: nope\n" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      match Policy.parse_file path with
      | Error [ msg ] ->
          Alcotest.(check bool) "mentions line" true (String.contains msg '1')
      | Error errors ->
          Alcotest.failf "expected one error, got %d" (List.length errors)
      | Ok _ -> Alcotest.fail "expected error")

let test_evaluate_policy_violations () =
  let violations =
    Policy.evaluate ~timezone:Timezone.utc ~from:(time 2024 1 1 0 0)
      ~until:(time 2024 1 2 0 0)
      [
        Policy.forbid_every_minute;
        Policy.require_timezone;
        Option.get (Policy.max_frequency_per_hour 12);
        Policy.disallow_midnight_utc;
      ]
      [ job "* * * * *"; job "0 0 * * *" ]
  in
  let rules =
    List.map (fun v -> Policy.rule_to_string v.Policy.rule) violations
  in
  Alcotest.(check bool)
    "every minute" true
    (List.mem "forbid_every_minute" rules);
  Alcotest.(check bool) "timezone" true (List.mem "require_timezone" rules);
  Alcotest.(check bool)
    "frequency" true
    (List.mem "max_frequency_per_hour" rules);
  Alcotest.(check bool) "midnight" true (List.mem "disallow_midnight_utc" rules)

let test_require_timezone_accepts_job_timezone () =
  let timezone =
    match Timezone.parse "America/New_York" with
    | Ok tz -> tz
    | Error msg -> Alcotest.fail msg
  in
  let violations =
    Policy.evaluate ~timezone:Timezone.utc ~from:(time 2024 1 1 0 0)
      ~until:(time 2024 1 2 0 0)
      [ Policy.require_timezone ]
      [ job ~timezone "0 9 * * *" ]
  in
  Alcotest.(check int) "violations" 0 (List.length violations)

let test_midnight_utc_uses_job_timezone () =
  let timezone =
    match Timezone.parse "America/New_York" with
    | Ok tz -> tz
    | Error msg -> Alcotest.fail msg
  in
  let violations =
    Policy.evaluate ~timezone:Timezone.utc ~from:(time 2024 1 1 0 0)
      ~until:(time 2024 1 2 0 0)
      [ Policy.disallow_midnight_utc ]
      [ job ~timezone "0 0 * * *" ]
  in
  Alcotest.(check int) "violations" 0 (List.length violations)

let test_forbid_every_minute_equivalent_forms () =
  let violations =
    Policy.evaluate ~timezone:Timezone.utc ~from:(time 2024 1 1 0 0)
      ~until:(time 2024 1 1 1 0)
      [ Policy.forbid_every_minute ]
      [ job "*/1 * * * *"; job "0-59 * * * *"; job "0 * * * * ?" ]
  in
  Alcotest.(check int) "violations" 3 (List.length violations)

let test_midnight_utc_respects_window () =
  let violations =
    Policy.evaluate ~timezone:Timezone.utc ~from:(time 2024 1 1 1 0)
      ~until:(time 2024 1 1 2 0)
      [ Policy.disallow_midnight_utc ]
      [ job "0 0 * * *" ]
  in
  Alcotest.(check int) "violations" 0 (List.length violations)

let () =
  Alcotest.run "policy"
    [
      ( "parse",
        [
          Alcotest.test_case "policy file" `Quick test_parse_policy_file;
          Alcotest.test_case "policy error" `Quick test_parse_policy_error;
        ] );
      ( "evaluate",
        [
          Alcotest.test_case "violations" `Quick test_evaluate_policy_violations;
          Alcotest.test_case "explicit timezone" `Quick
            test_require_timezone_accepts_job_timezone;
          Alcotest.test_case "midnight UTC uses job timezone" `Quick
            test_midnight_utc_uses_job_timezone;
          Alcotest.test_case "equivalent every-minute forms" `Quick
            test_forbid_every_minute_equivalent_forms;
          Alcotest.test_case "midnight UTC respects window" `Quick
            test_midnight_utc_respects_window;
        ] );
    ]
