open Croncheck_lib

let ptime =
  Alcotest.testable
    (fun ppf t ->
      Format.pp_print_string ppf (Ptime.to_rfc3339 ~tz_offset_s:0 t))
    Ptime.equal

let expr s =
  match Cron.parse s with
  | Ok e -> e
  | Error e -> Alcotest.fail (Cron.parse_error_to_string e)

let time y m d h min =
  Option.get (Ptime.of_date_time ((y, m, d), ((h, min, 0), 0)))

let test_every_minute () =
  let times = Schedule.next_n (expr "* * * * *") ~from:(time 2024 1 1 0 0) 5 in
  let expected =
    [
      time 2024 1 1 0 1;
      time 2024 1 1 0 2;
      time 2024 1 1 0 3;
      time 2024 1 1 0 4;
      time 2024 1 1 0 5;
    ]
  in
  Alcotest.(check (list ptime)) "next five" expected times

let test_never_fires () =
  let times =
    Schedule.next_n (expr "0 0 31 2 *") ~from:(time 2024 1 1 0 0) 10
  in
  Alcotest.(check int) "empty" 0 (List.length times)

let test_weekdays () =
  let from = time 2024 1 1 0 0 in
  let until = time 2024 1 7 23 59 in
  let times = Schedule.within (expr "0 9 * * 1-5") ~from ~until in
  Alcotest.(check int) "mon-fri" 5 (List.length times)

let test_ascending () =
  let times =
    Schedule.next_n (expr "*/7 * * * *") ~from:(time 2024 1 1 0 0) 20
  in
  let rec strictly = function
    | a :: (b :: _ as rest) -> Ptime.compare a b < 0 && strictly rest
    | _ -> true
  in
  Alcotest.(check bool) "ascending" true (strictly times)

let test_timezone_offset () =
  let timezone = Timezone.Fixed_offset (2 * 60 * 60) in
  let times =
    Schedule.next_n ~timezone (expr "0 9 * * *") ~from:(time 2024 1 1 6 58) 1
  in
  Alcotest.(check (list ptime))
    "09:00 +02 is 07:00Z"
    [ time 2024 1 1 7 0 ]
    times

let test_quartz_seconds () =
  let times =
    Schedule.next_n (expr "30 0 9 ? * 1 2024") ~from:(time 2024 1 1 8 59) 1
  in
  let expected =
    Option.get (Ptime.of_date_time ((2024, 1, 1), ((9, 0, 30), 0)))
  in
  Alcotest.(check (list ptime)) "quartz seconds" [ expected ] times

let test_quartz_past_year_stops () =
  let times =
    Schedule.next_n (expr "0 0 0 * * ? 2024") ~from:(time 2025 1 1 0 0) 1
  in
  Alcotest.(check (list ptime)) "past year" [] times

let test_names_schedule () =
  let times =
    Schedule.next_n (expr "0 9 * JAN MON") ~from:(time 2023 12 31 23 59) 2
  in
  Alcotest.(check (list ptime))
    "january mondays"
    [ time 2024 1 1 9 0; time 2024 1 8 9 0 ]
    times

let test_named_step_schedule () =
  let times =
    Schedule.next_n
      (expr "0 9 * JAN-DEC/2 MON-FRI/2")
      ~from:(time 2023 12 31 23 59) 3
  in
  Alcotest.(check (list ptime))
    "odd month mon/wed/fri"
    [ time 2024 1 1 9 0; time 2024 1 3 9 0; time 2024 1 5 9 0 ]
    times

let test_macro_schedule () =
  let times = Schedule.next_n (expr "@daily") ~from:(time 2024 1 1 12 0) 2 in
  Alcotest.(check (list ptime))
    "daily macro"
    [ time 2024 1 2 0 0; time 2024 1 3 0 0 ]
    times

let () =
  Alcotest.run "schedule"
    [
      ( "schedule",
        [
          Alcotest.test_case "every minute" `Quick test_every_minute;
          Alcotest.test_case "never fires" `Quick test_never_fires;
          Alcotest.test_case "weekdays" `Quick test_weekdays;
          Alcotest.test_case "ascending" `Quick test_ascending;
          Alcotest.test_case "timezone offset" `Quick test_timezone_offset;
          Alcotest.test_case "quartz seconds" `Quick test_quartz_seconds;
          Alcotest.test_case "quartz past year stops" `Quick
            test_quartz_past_year_stops;
          Alcotest.test_case "names" `Quick test_names_schedule;
          Alcotest.test_case "named steps" `Quick test_named_step_schedule;
          Alcotest.test_case "macros" `Quick test_macro_schedule;
        ] );
    ]
