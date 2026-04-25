open Croncheck_lib

let time y m d h min =
  Option.get (Ptime.of_date_time ((y, m, d), ((h, min, 0), 0)))

let job ?timezone ?id s =
  match Job.make ?timezone ?id ~source:Job.Stdin s with
  | Ok job -> job
  | Error e -> Alcotest.fail (Cron.parse_error_to_string e)

let test_load_buckets_and_busiest_order () =
  let jobs =
    [ job ~id:"five" "*/5 * * * *"; job ~id:"quarter" "*/15 * * * *" ]
  in
  let report =
    Load.analyze ~timezone:Timezone.utc ~from:(time 2024 1 1 0 0)
      ~until:(time 2024 1 1 0 15) ~bucket_seconds:3600 jobs
  in
  let busiest = Load.busiest report in
  Alcotest.(check int) "bucket count" 1 (List.length busiest);
  match busiest with
  | [ bucket ] ->
      Alcotest.(check int) "fires" 4 bucket.Load.fire_count;
      Alcotest.(check (list string))
        "jobs" [ "five:3"; "quarter:1" ]
        (List.map
           (fun job_count ->
             Printf.sprintf "%s:%d"
               (Job.label job_count.Load.job)
               job_count.fires)
           bucket.job_counts)
  | _ -> Alcotest.fail "expected one bucket"

let test_load_respects_job_timezone () =
  let timezone =
    match Timezone.parse "+02:00" with
    | Ok tz -> tz
    | Error msg -> Alcotest.fail msg
  in
  let jobs = [ job ~id:"local" ~timezone "0 9 * * *" ] in
  let report =
    Load.analyze ~timezone:Timezone.utc ~from:(time 2024 1 1 6 0)
      ~until:(time 2024 1 1 8 0) ~bucket_seconds:3600 jobs
  in
  match Load.busiest report with
  | [ bucket ] ->
      Alcotest.(check string)
        "start" "2024-01-01T07:00:00Z"
        (Output.string_of_time bucket.start)
  | _ -> Alcotest.fail "expected one bucket"

let () =
  Alcotest.run "load"
    [
      ( "analysis",
        [
          Alcotest.test_case "buckets and busiest order" `Quick
            test_load_buckets_and_busiest_order;
          Alcotest.test_case "respects job timezone" `Quick
            test_load_respects_job_timezone;
        ] );
    ]
