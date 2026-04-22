open Croncheck_lib

let expr s =
  match Cron.parse s with
  | Ok expr -> expr
  | Error e -> Alcotest.fail (Cron.parse_error_to_string e)

let test_parse_valid () =
  List.iter
    (fun raw ->
      match Cron.parse raw with
      | Ok _ -> ()
      | Error e -> Alcotest.fail (Cron.parse_error_to_string e))
    [
      "* * * * *";
      "0 0 * * *";
      "*/5 * * * *";
      "0 9-17 * * 1-5";
      "0,30 * * * *";
      "0 9 * JAN MON";
      "0 9 * JAN-MAR MON-FRI";
      "05 09 * jan mon";
      "0 9 * JAN,MAR,12 MON,WED,5";
      "0 9 * JAN-DEC/2 MON-FRI/2";
      "@hourly";
      "@daily";
      "@weekly";
      "@monthly";
      "@yearly";
      "@annually";
      "@midnight";
    ]

let test_parse_quartz () =
  match Cron.parse "30 0 9 ? * 1 2024" with
  | Ok (Cron.Quartz expr) ->
      Alcotest.(check bool) "has year" true (expr.year <> None)
  | Ok (Cron.Posix _) -> Alcotest.fail "expected quartz expression"
  | Error e -> Alcotest.fail (Cron.parse_error_to_string e)

let test_parse_invalid () =
  let cases =
    [ "* * * *"; "60 * * * *"; "*/x * * * *"; "0 0 1- * *"; "@reboot" ]
  in
  List.iter
    (fun raw ->
      match Cron.parse raw with
      | Ok _ -> Alcotest.failf "expected parse failure for %s" raw
      | Error _ -> ())
    cases

let test_parse_invalid_quartz_day_fields () =
  match Cron.parse "0 0 0 ? * ?" with
  | Ok _ -> Alcotest.fail "expected both Quartz day fields unspecified to fail"
  | Error _ -> ()

let test_expand () =
  Alcotest.(check (list int)) "any" [ 0; 1; 2 ] (Cron.expand Any ~min:0 ~max:2);
  Alcotest.(check (list int))
    "value" [ 5 ]
    (Cron.expand (Value 5) ~min:0 ~max:10);
  Alcotest.(check (list int))
    "range" [ 1; 2; 3 ]
    (Cron.expand (Range (1, 3)) ~min:0 ~max:10);
  Alcotest.(check (list int))
    "step any" [ 0; 5; 10 ]
    (Cron.expand (Step (Any, 5)) ~min:0 ~max:10);
  Alcotest.(check (list int))
    "step range" [ 1; 3; 5 ]
    (Cron.expand (Step (Range (1, 5), 2)) ~min:0 ~max:10);
  Alcotest.(check (list int))
    "list" [ 1; 3; 5 ]
    (Cron.expand (List [ Value 5; Value 1; Value 3 ]) ~min:0 ~max:10)

let test_parse_names () =
  match Cron.parse "0 9 * JAN-MAR MON-FRI" with
  | Ok (Cron.Posix expr) ->
      Alcotest.(check (list int))
        "months" [ 1; 2; 3 ]
        (Cron.expand expr.month ~min:1 ~max:12);
      Alcotest.(check (list int))
        "dows" [ 1; 2; 3; 4; 5 ]
        (Cron.expand expr.dow ~min:0 ~max:7)
  | Ok (Cron.Quartz _) -> Alcotest.fail "expected posix expression"
  | Error e -> Alcotest.fail (Cron.parse_error_to_string e)

let test_parse_mixed_names () =
  match Cron.parse "05 09 * JAN,MAR,12 MON,WED,5" with
  | Ok (Cron.Posix expr) ->
      Alcotest.(check (list int))
        "months" [ 1; 3; 12 ]
        (Cron.expand expr.month ~min:1 ~max:12);
      Alcotest.(check (list int))
        "dows" [ 1; 3; 5 ]
        (Cron.expand expr.dow ~min:0 ~max:7);
      Alcotest.(check (list int))
        "minute" [ 5 ]
        (Cron.expand expr.minute ~min:0 ~max:59);
      Alcotest.(check (list int))
        "hour" [ 9 ]
        (Cron.expand expr.hour ~min:0 ~max:23)
  | Ok (Cron.Quartz _) -> Alcotest.fail "expected posix expression"
  | Error e -> Alcotest.fail (Cron.parse_error_to_string e)

let test_parse_named_steps () =
  match Cron.parse "0 9 * JAN-DEC/2 MON-FRI/2" with
  | Ok (Cron.Posix expr) ->
      Alcotest.(check (list int))
        "months" [ 1; 3; 5; 7; 9; 11 ]
        (Cron.expand expr.month ~min:1 ~max:12);
      Alcotest.(check (list int))
        "dows" [ 1; 3; 5 ]
        (Cron.expand expr.dow ~min:0 ~max:7)
  | Ok (Cron.Quartz _) -> Alcotest.fail "expected posix expression"
  | Error e -> Alcotest.fail (Cron.parse_error_to_string e)

let test_parse_macro () =
  match Cron.parse "@hourly" with
  | Ok (Cron.Posix expr) ->
      Alcotest.(check (list int))
        "minute" [ 0 ]
        (Cron.expand expr.minute ~min:0 ~max:59);
      Alcotest.(check (list int))
        "hour" (List.init 24 Fun.id)
        (Cron.expand expr.hour ~min:0 ~max:23)
  | Ok (Cron.Quartz _) -> Alcotest.fail "expected posix expression"
  | Error e -> Alcotest.fail (Cron.parse_error_to_string e)

let time y m d = Option.get (Ptime.of_date_time ((y, m, d), ((0, 0, 0), 0)))

let test_dom_dow_or () =
  let e = expr "0 0 15 * 1" in
  Alcotest.(check bool)
    "matches 15th" true
    (Schedule.matches e (time 2024 1 15));
  Alcotest.(check bool)
    "matches monday" true
    (Schedule.matches e (time 2024 1 22));
  Alcotest.(check bool)
    "does not match unrelated day" false
    (Schedule.matches e (time 2024 1 16))

let test_dom_star_dow_restricted () =
  let e = expr "0 0 * * MON" in
  Alcotest.(check bool)
    "matches monday" true
    (Schedule.matches e (time 2024 1 22));
  Alcotest.(check bool)
    "does not match non-monday" false
    (Schedule.matches e (time 2024 1 23))

let test_dom_restricted_dow_star () =
  let e = expr "0 0 15 * *" in
  Alcotest.(check bool)
    "matches fifteenth" true
    (Schedule.matches e (time 2024 1 15));
  Alcotest.(check bool)
    "does not match other day" false
    (Schedule.matches e (time 2024 1 16))

let test_dow_seven_range () =
  let e = expr "0 0 * * 5-7" in
  Alcotest.(check bool) "friday" true (Schedule.matches e (time 2024 1 5));
  Alcotest.(check bool) "saturday" true (Schedule.matches e (time 2024 1 6));
  Alcotest.(check bool) "sunday" true (Schedule.matches e (time 2024 1 7));
  Alcotest.(check bool) "monday" false (Schedule.matches e (time 2024 1 8))

let () =
  Alcotest.run "cron"
    [
      ( "parse",
        [
          Alcotest.test_case "valid" `Quick test_parse_valid;
          Alcotest.test_case "quartz" `Quick test_parse_quartz;
          Alcotest.test_case "invalid" `Quick test_parse_invalid;
          Alcotest.test_case "invalid quartz day fields" `Quick
            test_parse_invalid_quartz_day_fields;
        ] );
      ("expand", [ Alcotest.test_case "fields" `Quick test_expand ]);
      ( "extensions",
        [
          Alcotest.test_case "names" `Quick test_parse_names;
          Alcotest.test_case "mixed names" `Quick test_parse_mixed_names;
          Alcotest.test_case "named steps" `Quick test_parse_named_steps;
          Alcotest.test_case "macros" `Quick test_parse_macro;
        ] );
      ( "semantics",
        [
          Alcotest.test_case "dom dow or" `Quick test_dom_dow_or;
          Alcotest.test_case "dom star dow restricted" `Quick
            test_dom_star_dow_restricted;
          Alcotest.test_case "dom restricted dow star" `Quick
            test_dom_restricted_dow_star;
          Alcotest.test_case "dow seven range" `Quick test_dow_seven_range;
        ] );
    ]
