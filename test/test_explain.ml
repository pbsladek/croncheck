open Croncheck_lib

let parse s = match Cron.parse s with Ok e -> e | Error _ -> invalid_arg s

let check label expected raw =
  Alcotest.(check string) label expected (Explain.describe (parse raw))

let test_every_minute () = check "every minute" "every minute" "* * * * *"

let test_every_n_minutes () =
  check "every 5 min" "every 5 minutes" "*/5 * * * *";
  check "every 15 min" "every 15 minutes" "*/15 * * * *"

let test_top_of_hour () =
  check "top of hour" "at the top of every hour" "0 * * * *"

let test_at_minute_past_hour () =
  check "minute past hour" "at minute 30 of every hour" "30 * * * *"

let test_midnight () = check "midnight" "at midnight" "0 0 * * *"
let test_noon () = check "noon" "at noon" "0 12 * * *"

let test_specific_time () =
  check "9 AM" "at 9:00 AM" "0 9 * * *";
  check "6 PM" "at 6:00 PM" "0 18 * * *";
  check "1:30 PM" "at 1:30 PM" "30 13 * * *"

let test_with_dow () =
  check "weekdays" "at 9:00 AM on Monday through Friday" "0 9 * * 1-5";
  check "monday" "at midnight on Monday" "0 0 * * 1"

let test_with_dom () =
  check "first of month" "at midnight on 1st" "0 0 1 * *";
  check "31st" "at midnight on 31st" "0 0 31 * *"

let test_with_month () =
  check "january" "at midnight in January" "0 0 * 1 *";
  check "december" "at midnight in December" "0 0 * 12 *"

let test_dom_and_dow () =
  check "dom and dow" "at midnight on 1st or Monday" "0 0 1 * 1"

let test_month_range () =
  check "month range" "at midnight in January through March" "0 0 * 1-3 *"

let test_every_minute_during_hour () =
  check "every minute hour 9" "every minute during hour 9" "* 9 * * *"

let test_every_n_minutes_during_hour () =
  check "every 5 min hour 9" "every 5 minutes during hour 9" "*/5 9 * * *"

let () =
  Alcotest.run "explain"
    [
      ( "basic",
        [
          Alcotest.test_case "every minute" `Quick test_every_minute;
          Alcotest.test_case "every N minutes" `Quick test_every_n_minutes;
          Alcotest.test_case "top of hour" `Quick test_top_of_hour;
          Alcotest.test_case "minute past hour" `Quick test_at_minute_past_hour;
          Alcotest.test_case "midnight" `Quick test_midnight;
          Alcotest.test_case "noon" `Quick test_noon;
          Alcotest.test_case "specific time" `Quick test_specific_time;
        ] );
      ( "with-day",
        [
          Alcotest.test_case "day-of-week" `Quick test_with_dow;
          Alcotest.test_case "day-of-month" `Quick test_with_dom;
          Alcotest.test_case "dom and dow" `Quick test_dom_and_dow;
        ] );
      ( "with-month",
        [
          Alcotest.test_case "month value" `Quick test_with_month;
          Alcotest.test_case "month range" `Quick test_month_range;
        ] );
      ( "complex",
        [
          Alcotest.test_case "every minute during hour" `Quick
            test_every_minute_during_hour;
          Alcotest.test_case "every N minutes during hour" `Quick
            test_every_n_minutes_during_hour;
        ] );
    ]
