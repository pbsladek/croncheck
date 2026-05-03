type rule =
  | ForbidEveryMinute
  | RequireTimezone
  | MaxFrequencyPerHour of int
  | DisallowMidnightUtc

type t = rule list
type config = { rules : t; fail_on : string list option }
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

let valid_fail_on =
  [ "all"; "none"; "warnings"; "conflicts"; "overlaps"; "policy" ]

let parse_fail_on line_no value =
  (* Keep policy-file execution settings in their textual form.  The CLI layer
     owns the mapping to [Check.finding_kind], avoiding a dependency cycle. *)
  let categories =
    value |> String.split_on_char ','
    |> List.map (fun s -> String.trim (String.lowercase_ascii s))
    |> List.filter (( <> ) "")
  in
  match
    List.find_opt
      (fun category -> not (List.mem category valid_fail_on))
      categories
  with
  | Some category ->
      Error
        (Printf.sprintf
           "line %d: unknown fail_on category %S; expected all, none, \
            warnings, conflicts, overlaps, or policy"
           line_no category)
  | None -> Ok (List.sort_uniq String.compare categories)

type parsed_line = Rule of rule option | Fail_on of string list

let parse_rule line_no raw =
  match String.index_opt raw ':' with
  | None -> Error (Printf.sprintf "line %d: expected key: value" line_no)
  | Some idx -> (
      let key = String.sub raw 0 idx |> trim in
      let value =
        String.sub raw (idx + 1) (String.length raw - idx - 1) |> trim
      in
      match key with
      | "fail_on" ->
          Result.map
            (fun categories -> Fail_on categories)
            (parse_fail_on line_no value)
      | "forbid_every_minute" -> (
          match parse_bool value with
          | Ok true -> Ok (Rule (Some ForbidEveryMinute))
          | Ok false -> Ok (Rule None)
          | Error msg -> Error (Printf.sprintf "line %d: %s" line_no msg))
      | "require_timezone" -> (
          match parse_bool value with
          | Ok true -> Ok (Rule (Some RequireTimezone))
          | Ok false -> Ok (Rule None)
          | Error msg -> Error (Printf.sprintf "line %d: %s" line_no msg))
      | "max_frequency_per_hour" -> (
          match int_of_string_opt value with
          | Some n when n >= 0 -> Ok (Rule (max_frequency_per_hour n))
          | _ ->
              Error
                (Printf.sprintf "line %d: expected non-negative integer" line_no)
          )
      | "disallow_midnight_utc" -> (
          match parse_bool value with
          | Ok true -> Ok (Rule (Some DisallowMidnightUtc))
          | Ok false -> Ok (Rule None)
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

let parse_config_file path =
  match read_lines path with
  | lines ->
      let rules, fail_on, errors =
        lines
        |> List.mapi (fun i line -> (i + 1, trim line))
        |> List.fold_left
             (fun (rules, fail_on, errors) (line_no, line) ->
               if line = "" || String.starts_with ~prefix:"#" line then
                 (rules, fail_on, errors)
               else
                 match parse_rule line_no line with
                 | Ok (Rule None) -> (rules, fail_on, errors)
                 | Ok (Rule (Some rule)) -> (rule :: rules, fail_on, errors)
                 | Ok (Fail_on categories) -> (rules, Some categories, errors)
                 | Error error -> (rules, fail_on, error :: errors))
             ([], None, [])
      in
      if errors = [] then Ok { rules = List.rev rules; fail_on }
      else Error (List.rev errors)
  | exception Sys_error message -> Error [ message ]

let parse_file path =
  Result.map (fun config -> config.rules) (parse_config_file path)

let field_count field ~min ~max = List.length (Cron.expand field ~min ~max)

let field_covers field ~min ~max =
  (* Use semantic expansion rather than raw syntax so equivalent schedules such
     as [*], [*/1], and a complete explicit range behave the same. *)
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
  (* Scan only the active analysis window.  A midnight outside the window should
     not make this CI run fail. *)
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
