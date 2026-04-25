type rule =
  | ForbidEveryMinute
  | RequireTimezone
  | MaxFrequencyPerHour of int
  | DisallowMidnightUtc

type t = rule list
type violation = { job : Job.t; rule : rule; message : string }

let default = []
let forbid_every_minute = ForbidEveryMinute
let require_timezone = RequireTimezone
let disallow_midnight_utc = DisallowMidnightUtc

let max_frequency_per_hour n =
  if n >= 0 then Some (MaxFrequencyPerHour n) else None

let trim = String.trim

let parse_bool raw =
  match String.lowercase_ascii (trim raw) with
  | "true" | "yes" | "on" -> Ok true
  | "false" | "no" | "off" -> Ok false
  | value -> Error (Printf.sprintf "expected boolean, got %S" value)

let parse_rule line_no raw =
  match String.index_opt raw ':' with
  | None -> Error (Printf.sprintf "line %d: expected key: value" line_no)
  | Some idx -> (
      let key = String.sub raw 0 idx |> trim in
      let value =
        String.sub raw (idx + 1) (String.length raw - idx - 1) |> trim
      in
      match key with
      | "forbid_every_minute" -> (
          match parse_bool value with
          | Ok true -> Ok (Some ForbidEveryMinute)
          | Ok false -> Ok None
          | Error msg -> Error (Printf.sprintf "line %d: %s" line_no msg))
      | "require_timezone" -> (
          match parse_bool value with
          | Ok true -> Ok (Some RequireTimezone)
          | Ok false -> Ok None
          | Error msg -> Error (Printf.sprintf "line %d: %s" line_no msg))
      | "max_frequency_per_hour" -> (
          match int_of_string_opt value with
          | Some n when n >= 0 -> Ok (max_frequency_per_hour n)
          | _ ->
              Error
                (Printf.sprintf "line %d: expected non-negative integer" line_no)
          )
      | "disallow_midnight_utc" -> (
          match parse_bool value with
          | Ok true -> Ok (Some DisallowMidnightUtc)
          | Ok false -> Ok None
          | Error msg -> Error (Printf.sprintf "line %d: %s" line_no msg))
      | _ -> Error (Printf.sprintf "line %d: unknown policy key %S" line_no key)
      )

let read_lines path =
  let ic = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let rec loop acc =
        match input_line ic with
        | line -> loop (line :: acc)
        | exception End_of_file -> List.rev acc
      in
      loop [])

let parse_file path =
  match read_lines path with
  | lines ->
      let rules, errors =
        lines
        |> List.mapi (fun i line -> (i + 1, trim line))
        |> List.fold_left
             (fun (rules, errors) (line_no, line) ->
               if line = "" || String.starts_with ~prefix:"#" line then
                 (rules, errors)
               else
                 match parse_rule line_no line with
                 | Ok None -> (rules, errors)
                 | Ok (Some rule) -> (rule :: rules, errors)
                 | Error error -> (rules, error :: errors))
             ([], [])
      in
      if errors = [] then Ok (List.rev rules) else Error (List.rev errors)
  | exception Sys_error message -> Error [ message ]

let field_count field ~min ~max = List.length (Cron.expand field ~min ~max)

let field_covers field ~min ~max =
  let values = Cron.expand field ~min ~max in
  List.for_all
    (fun n -> List.mem n values)
    (List.init (max - min + 1) (( + ) min))

let fires_per_hour = function
  | Cron.Posix expr -> field_count expr.minute ~min:0 ~max:59
  | Quartz expr ->
      field_count expr.minute ~min:0 ~max:59
      * field_count expr.second ~min:0 ~max:59

let day_field_covers field ~min ~max =
  let values = Cron.day_field_values field ~min ~max in
  List.for_all
    (fun n -> List.mem n values)
    (List.init (max - min + 1) (( + ) min))

let posix_matches_every_day (expr : Cron.posix) =
  (field_covers expr.Cron.dom ~min:1 ~max:31 && expr.dow = Cron.Any)
  || (expr.dom = Cron.Any && field_covers expr.dow ~min:0 ~max:6)
  || (expr.dom = Cron.Any && expr.dow = Cron.Any)

let quartz_matches_every_day (expr : Cron.quartz) =
  day_field_covers expr.Cron.dom ~min:1 ~max:31
  && not (Cron.day_field_is_specific expr.dow)
  || (not (Cron.day_field_is_specific expr.dom))
     && day_field_covers expr.dow ~min:0 ~max:6

let fires_at_least_every_minute = function
  | Cron.Posix expr ->
      field_covers expr.minute ~min:0 ~max:59
      && field_covers expr.hour ~min:0 ~max:23
      && field_covers expr.month ~min:1 ~max:12
      && posix_matches_every_day expr
  | Quartz expr ->
      field_count expr.second ~min:0 ~max:59 >= 1
      && field_covers expr.minute ~min:0 ~max:59
      && field_covers expr.hour ~min:0 ~max:23
      && field_covers expr.month ~min:1 ~max:12
      && expr.year = None
      && quartz_matches_every_day expr

let effective_timezone fallback job =
  Option.value job.Job.timezone ~default:fallback

let fires_at_midnight_utc ~timezone ~from ~until job =
  let rec loop seq =
    match seq () with
    | Seq.Nil -> false
    | Seq.Cons (t, rest) ->
        if Ptime.compare t until > 0 then false
        else
          let _, ((hour, minute, second), _) = Ptime.to_date_time t in
          (hour = 0 && minute = 0 && second = 0) || loop rest
  in
  loop (Schedule.fire_times ~timezone job.Job.expr ~from)

let rule_to_string = function
  | ForbidEveryMinute -> "forbid_every_minute"
  | RequireTimezone -> "require_timezone"
  | MaxFrequencyPerHour _ -> "max_frequency_per_hour"
  | DisallowMidnightUtc -> "disallow_midnight_utc"

let violation job rule message = { job; rule; message }

let evaluate ~timezone ~from ~until policy jobs =
  List.concat_map
    (fun job ->
      List.filter_map
        (function
          | ForbidEveryMinute ->
              if fires_at_least_every_minute job.Job.expr then
                Some
                  (violation job ForbidEveryMinute
                     "every-minute schedules are not allowed")
              else None
          | RequireTimezone ->
              if job.Job.timezone = None then
                Some
                  (violation job RequireTimezone
                     "job must specify an explicit timezone")
              else None
          | MaxFrequencyPerHour limit ->
              let per_hour = fires_per_hour job.Job.expr in
              if per_hour > limit then
                Some
                  (violation job (MaxFrequencyPerHour limit)
                     (Printf.sprintf "fires %d times/hour, above limit %d"
                        per_hour limit))
              else None
          | DisallowMidnightUtc ->
              let job_timezone = effective_timezone timezone job in
              if fires_at_midnight_utc ~timezone:job_timezone ~from ~until job
              then
                Some (violation job DisallowMidnightUtc "fires at midnight UTC")
              else None)
        policy)
    jobs
