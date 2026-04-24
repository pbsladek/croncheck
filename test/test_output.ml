open Croncheck_lib

let ptime s =
  match Ptime.of_rfc3339 s with Ok (t, _, _) -> t | Error _ -> invalid_arg s

let contains needle haystack =
  let n = String.length needle and h = String.length haystack in
  let rec find i =
    i + n <= h && (String.sub haystack i n = needle || find (i + 1))
  in
  find 0

let capture f =
  let buf = Buffer.create 64 in
  let ppf = Format.formatter_of_buffer buf in
  f ppf;
  Format.pp_print_flush ppf ();
  Buffer.contents buf

(* string_of_time *)

let test_rfc3339_default () =
  let t = ptime "2026-04-22T06:20:00Z" in
  Alcotest.(check string)
    "rfc3339" "2026-04-22T06:20:00Z" (Output.string_of_time t)

let test_human_utc () =
  let t = ptime "2026-04-22T06:20:00Z" in
  Alcotest.(check string)
    "human" "April 22 Wed 2026 at 6:20 AM UTC"
    (Output.string_of_time ~time_format:Output.Human t)

let test_human_fixed_offset () =
  let t = ptime "2026-04-22T07:00:00Z" in
  let timezone =
    match Timezone.parse "+02:00" with
    | Ok tz -> tz
    | Error msg -> invalid_arg msg
  in
  Alcotest.(check string)
    "human offset" "April 22 Wed 2026 at 9:00 AM +02:00"
    (Output.string_of_time ~timezone ~time_format:Output.Human t)

let test_human_midnight_noon_and_seconds () =
  let midnight = ptime "2026-04-22T00:00:00Z" in
  let noon = ptime "2026-04-22T12:00:00Z" in
  let with_seconds = ptime "2026-04-22T12:30:15Z" in
  let human = Output.string_of_time ~time_format:Human in
  Alcotest.(check string)
    "midnight" "April 22 Wed 2026 at 12:00 AM UTC" (human midnight);
  Alcotest.(check string)
    "noon" "April 22 Wed 2026 at 12:00 PM UTC" (human noon);
  Alcotest.(check string)
    "seconds" "April 22 Wed 2026 at 12:30:15 PM UTC" (human with_seconds)

(* warning_to_string *)

let test_warning_to_string () =
  let check label expected w =
    Alcotest.(check string) label expected (Output.warning_to_string w)
  in
  check "never fires" "never fires" Analysis.NeverFires;
  check "rarely fires" "rarely fires (4 times/year)"
    (Analysis.RarelyFires { times_per_year = 4 });
  check "dom dow"
    "day-of-month and day-of-week both restricted; POSIX cron uses OR semantics"
    Analysis.DomDowAmbiguity;
  check "high frequency" "high frequency (120 times/hour)"
    (Analysis.HighFrequency { per_hour = 120 });
  check "end of month trap"
    "end-of-month trap; selected days do not occur every month"
    Analysis.EndOfMonthTrap;
  check "leap year" "leap-year-only schedule" Analysis.LeapYearOnly

(* pp_warnings *)

let test_pp_warnings_plain_empty () =
  let out =
    capture (fun ppf ->
        Output.pp_warnings ppf ~format:Output.Plain ~expr:"0 0 * * *" [])
  in
  Alcotest.(check string) "no warnings" "No warnings for 0 0 * * *\n" out

let test_pp_warnings_plain_with_warnings () =
  let out =
    capture (fun ppf ->
        Output.pp_warnings ppf ~format:Output.Plain ~expr:"0 0 31 * *"
          [
            Analysis.EndOfMonthTrap; Analysis.RarelyFires { times_per_year = 7 };
          ])
  in
  Alcotest.(check bool)
    "has header" true
    (String.length out > 0 && String.sub out 0 8 = "Warnings");
  Alcotest.(check bool)
    "has trap warning" true
    (contains "end-of-month trap" out)

let test_pp_warnings_json () =
  let out =
    capture (fun ppf ->
        Output.pp_warnings ppf ~format:Output.Json ~expr:"0 0 31 * *"
          [ Analysis.EndOfMonthTrap ])
  in
  Alcotest.(check bool) "has expr key" true (contains "\"expr\"" out)

(* pp_conflicts *)

let test_pp_conflicts_plain_empty () =
  let out =
    capture (fun ppf -> Output.pp_conflicts ppf ~format:Output.Plain [])
  in
  Alcotest.(check string) "no conflicts" "No conflicts found\n" out

let test_pp_conflicts_plain_with_conflict () =
  let conflict =
    {
      Analysis.expr_a = "*/5 * * * *";
      expr_b = "*/3 * * * *";
      at = ptime "2024-01-01T00:15:00Z";
      delta = 0;
    }
  in
  let out =
    capture (fun ppf ->
        Output.pp_conflicts ppf ~format:Output.Plain [ conflict ])
  in
  Alcotest.(check bool) "has conflict at" true (contains "conflict at" out)

let test_pp_conflicts_json () =
  let conflict =
    {
      Analysis.expr_a = "*/5 * * * *";
      expr_b = "*/3 * * * *";
      at = ptime "2024-01-01T00:15:00Z";
      delta = 0;
    }
  in
  let out =
    capture (fun ppf ->
        Output.pp_conflicts ppf ~format:Output.Json [ conflict ])
  in
  Alcotest.(check bool) "has conflicts key" true (contains "\"conflicts\"" out)

(* pp_overlaps *)

let test_pp_overlaps_plain_empty () =
  let out =
    capture (fun ppf -> Output.pp_overlaps ppf ~format:Output.Plain [])
  in
  Alcotest.(check string) "no overlaps" "No overlaps found\n" out

let test_pp_overlaps_plain_with_overlap () =
  let overlap =
    {
      Analysis.started_at = ptime "2024-01-01T00:00:00Z";
      next_fire = ptime "2024-01-01T00:01:00Z";
      overrun_by = 60;
    }
  in
  let out =
    capture (fun ppf -> Output.pp_overlaps ppf ~format:Output.Plain [ overlap ])
  in
  Alcotest.(check bool) "has started" true (contains "started" out)

let test_pp_overlaps_json () =
  let overlap =
    {
      Analysis.started_at = ptime "2024-01-01T00:00:00Z";
      next_fire = ptime "2024-01-01T00:01:00Z";
      overrun_by = 60;
    }
  in
  let out =
    capture (fun ppf -> Output.pp_overlaps ppf ~format:Output.Json [ overlap ])
  in
  Alcotest.(check bool) "has overlaps key" true (contains "\"overlaps\"" out)

(* pp_check *)

let empty_report : Check.report =
  { jobs = []; warnings = []; conflicts = []; overlaps = [] }

let test_pp_check_plain_empty () =
  let out =
    capture (fun ppf ->
        Output.pp_check ~timezone:Timezone.utc ppf ~format:Output.Plain
          empty_report)
  in
  Alcotest.(check bool) "no jobs message" true (contains "No jobs found" out)

let test_pp_check_json_empty () =
  let out =
    capture (fun ppf ->
        Output.pp_check ~timezone:Timezone.utc ppf ~format:Output.Json
          empty_report)
  in
  Alcotest.(check bool) "has jobs key" true (contains "\"jobs\"" out)

let () =
  Alcotest.run "output"
    [
      ( "time-format",
        [
          Alcotest.test_case "rfc3339 default" `Quick test_rfc3339_default;
          Alcotest.test_case "human utc" `Quick test_human_utc;
          Alcotest.test_case "human fixed offset" `Quick test_human_fixed_offset;
          Alcotest.test_case "human midnight noon seconds" `Quick
            test_human_midnight_noon_and_seconds;
        ] );
      ( "warning-to-string",
        [ Alcotest.test_case "all variants" `Quick test_warning_to_string ] );
      ( "pp-warnings",
        [
          Alcotest.test_case "plain empty" `Quick test_pp_warnings_plain_empty;
          Alcotest.test_case "plain with warnings" `Quick
            test_pp_warnings_plain_with_warnings;
          Alcotest.test_case "json" `Quick test_pp_warnings_json;
        ] );
      ( "pp-conflicts",
        [
          Alcotest.test_case "plain empty" `Quick test_pp_conflicts_plain_empty;
          Alcotest.test_case "plain with conflict" `Quick
            test_pp_conflicts_plain_with_conflict;
          Alcotest.test_case "json" `Quick test_pp_conflicts_json;
        ] );
      ( "pp-overlaps",
        [
          Alcotest.test_case "plain empty" `Quick test_pp_overlaps_plain_empty;
          Alcotest.test_case "plain with overlap" `Quick
            test_pp_overlaps_plain_with_overlap;
          Alcotest.test_case "json" `Quick test_pp_overlaps_json;
        ] );
      ( "pp-check",
        [
          Alcotest.test_case "plain empty" `Quick test_pp_check_plain_empty;
          Alcotest.test_case "json empty" `Quick test_pp_check_json_empty;
        ] );
    ]
