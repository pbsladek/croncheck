let ptime s =
  match Ptime.of_rfc3339 s with Ok (t, _, _) -> t | Error _ -> invalid_arg s

let test_rfc3339_default () =
  let t = ptime "2026-04-22T06:20:00Z" in
  Alcotest.(check string)
    "rfc3339" "2026-04-22T06:20:00Z"
    (Croncheck_lib.Output.string_of_time t)

let test_human_utc () =
  let t = ptime "2026-04-22T06:20:00Z" in
  Alcotest.(check string)
    "human" "April 22 Wed 2026 at 6:20 AM UTC"
    (Croncheck_lib.Output.string_of_time ~time_format:Croncheck_lib.Output.Human
       t)

let test_human_fixed_offset () =
  let t = ptime "2026-04-22T07:00:00Z" in
  let timezone =
    match Croncheck_lib.Timezone.parse "+02:00" with
    | Ok timezone -> timezone
    | Error msg -> invalid_arg msg
  in
  Alcotest.(check string)
    "human offset" "April 22 Wed 2026 at 9:00 AM +02:00"
    (Croncheck_lib.Output.string_of_time ~timezone
       ~time_format:Croncheck_lib.Output.Human t)

let test_human_midnight_noon_and_seconds () =
  let midnight = ptime "2026-04-22T00:00:00Z" in
  let noon = ptime "2026-04-22T12:00:00Z" in
  let with_seconds = ptime "2026-04-22T12:30:15Z" in
  let human = Croncheck_lib.Output.string_of_time ~time_format:Human in
  Alcotest.(check string)
    "midnight" "April 22 Wed 2026 at 12:00 AM UTC" (human midnight);
  Alcotest.(check string)
    "noon" "April 22 Wed 2026 at 12:00 PM UTC" (human noon);
  Alcotest.(check string)
    "seconds" "April 22 Wed 2026 at 12:30:15 PM UTC" (human with_seconds)

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
    ]
