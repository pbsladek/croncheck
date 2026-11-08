open Croncheck_lib

let expr s =
  match Cron.parse s with
  | Ok e -> e
  | Error e -> Alcotest.fail (Cron.parse_error_to_string e)

let time y m d h min =
  Option.get (Ptime.of_date_time ((y, m, d), ((h, min, 0), 0)))

let has_warning pred warnings = List.exists pred warnings

let test_warn_end_of_month () =
  let warnings = Analysis.warn (expr "0 0 31 * *") in
  Alcotest.(check bool)
    "end of month" true
    (has_warning (( = ) Analysis.EndOfMonthTrap) warnings)

let test_warn_high_frequency () =
  let warnings = Analysis.warn (expr "* * * * *") in
  Alcotest.(check bool)
    "high frequency" true
    (has_warning
       (function Analysis.HighFrequency _ -> true | _ -> false)
       warnings)

let test_warn_quartz_high_frequency_seconds () =
  let warnings = Analysis.warn (expr "*/10 */2 * * * ?") in
  Alcotest.(check bool)
    "quartz seconds high frequency" true
    (has_warning
       (function
         | Analysis.HighFrequency { per_hour = 180 } -> true | _ -> false)
       warnings)

let test_warn_never () =
  let warnings = Analysis.warn (expr "0 0 30 2 *") in
  Alcotest.(check bool)
    "never" true
    (has_warning (( = ) Analysis.NeverFires) warnings)

let test_warn_dom_dow () =
  let warnings = Analysis.warn (expr "0 0 15 * 1") in
  Alcotest.(check bool)
    "dom dow" true
    (has_warning (( = ) Analysis.DomDowAmbiguity) warnings)

let test_warn_daily_clean () =
  let warnings = Analysis.warn (expr "0 0 * * *") in
  Alcotest.(check bool)
    "no leap-year false positive" false
    (has_warning
       (function Analysis.LeapYearOnly -> true | _ -> false)
       warnings)

let test_warn_quartz_question_clean () =
  let warnings = Analysis.warn (expr "0 0 9 ? * 1") in
  Alcotest.(check bool)
    "no posix ambiguity for quartz ?" false
    (has_warning (( = ) Analysis.DomDowAmbiguity) warnings)

let test_warn_quartz_leap_year () =
  let warnings = Analysis.warn (expr "0 0 0 29 2 ?") in
  Alcotest.(check bool)
    "quartz leap year" true
    (has_warning (( = ) Analysis.LeapYearOnly) warnings)

let test_conflicts () =
  let from = time 2023 12 31 23 59 in
  let until = time 2024 1 1 0 45 in
  let conflicts =
    Analysis.conflicts ~expr_a:(expr "*/5 * * * *") ~expr_b:(expr "*/3 * * * *")
      ~from ~until ~threshold:0
  in
  let minutes =
    List.map
      (fun c ->
        let _, ((_, minute, _), _) =
          Ptime.to_date_time ~tz_offset_s:0 c.Analysis.at
        in
        minute)
      conflicts
  in
  Alcotest.(check (list int)) "quarter hours" [ 0; 15; 30; 45 ] minutes

let test_overlaps () =
  let from = time 2024 1 1 0 0 in
  let until = time 2024 1 1 1 0 in
  let overlaps =
    Analysis.overlaps (expr "* * * * *") ~from ~until ~duration:120
  in
  Alcotest.(check int) "overlaps in one hour" 59 (List.length overlaps)

let test_bounded_sparse_analyses () =
  let future = expr "0 0 0 * * ? 2199" in
  let daily = expr "@daily" in
  let from = time 2024 1 1 0 0 in
  let until = time 2024 1 2 0 0 in
  Alcotest.(check int)
    "no conflicts in window" 0
    (List.length
       (Analysis.conflicts ~expr_a:future ~expr_b:daily ~from ~until
          ~threshold:0));
  Alcotest.(check int)
    "no overlaps in window" 0
    (List.length (Analysis.overlaps future ~from ~until ~duration:120));
  Alcotest.(check int)
    "no differences in empty window" 0
    (List.length (Analysis.diff future ~expr_b:future ~from ~until));
  let job = Result.get_ok (Job.make ~source:Job.Cli "0 0 0 * * ? 2199") in
  Alcotest.(check int)
    "no midnight policy violation in window" 0
    (List.length
       (Policy.evaluate ~timezone:Timezone.utc ~from ~until
          [ Policy.disallow_midnight_utc ]
          [ job ]))

let () =
  Alcotest.run "analysis"
    [
      ( "warn",
        [
          Alcotest.test_case "end of month" `Quick test_warn_end_of_month;
          Alcotest.test_case "high frequency" `Quick test_warn_high_frequency;
          Alcotest.test_case "quartz high frequency seconds" `Quick
            test_warn_quartz_high_frequency_seconds;
          Alcotest.test_case "never" `Quick test_warn_never;
          Alcotest.test_case "dom dow" `Quick test_warn_dom_dow;
          Alcotest.test_case "daily clean" `Quick test_warn_daily_clean;
          Alcotest.test_case "quartz question clean" `Quick
            test_warn_quartz_question_clean;
          Alcotest.test_case "quartz leap year" `Quick
            test_warn_quartz_leap_year;
        ] );
      ( "analysis",
        [
          Alcotest.test_case "conflicts" `Quick test_conflicts;
          Alcotest.test_case "overlaps" `Quick test_overlaps;
          Alcotest.test_case "bounded sparse analyses" `Quick
            test_bounded_sparse_analyses;
        ] );
    ]
