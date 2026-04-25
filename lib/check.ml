type source =
  | Stdin of string list
  | Crontab of { path : string; system : bool }
  | Kubernetes of string

type report = {
  jobs : Job.t list;
  warnings : (Job.t * Analysis.warning list) list;
  conflicts : Analysis.conflict list;
  overlaps : Analysis.overlap list;
}

type policy_report = {
  report : report;
  policy_violations : Policy.violation list;
}

let parse_stdin lines =
  let _, jobs, errors =
    List.fold_left
      (fun (line_no, jobs, errors) raw ->
        let line = String.trim raw in
        if line = "" || String.starts_with ~prefix:"#" line then
          (line_no + 1, jobs, errors)
        else
          match Job.make ~line:line_no ~source:Stdin line with
          | Ok job -> (line_no + 1, job :: jobs, errors)
          | Error e ->
              let msg =
                Printf.sprintf "stdin:%d: %s" line_no
                  (Cron.parse_error_to_string e)
              in
              (line_no + 1, jobs, msg :: errors))
      (1, [], []) lines
  in
  match errors with
  | [] -> Ok (List.rev jobs)
  | errors -> Error (List.rev errors)

let load = function
  | Stdin lines -> parse_stdin lines
  | Crontab { path; system } -> (
      match Crontab.parse_file ~system path with
      | Ok jobs -> Ok jobs
      | Error errors ->
          errors
          |> List.map (fun (e : Crontab.error) ->
              match e.line with
              | Some line -> Printf.sprintf "%s:%d: %s" path line e.message
              | None -> Printf.sprintf "%s: %s" path e.message)
          |> Result.error)
  | Kubernetes path -> (
      match Kubernetes.parse_file path with
      | Ok jobs -> Ok jobs
      | Error errors ->
          errors
          |> List.map (fun (e : Kubernetes.error) ->
              match e.line with
              | Some line -> Printf.sprintf "%s:%d: %s" e.file line e.message
              | None -> Printf.sprintf "%s: %s" e.file e.message)
          |> Result.error)

let job_timezone fallback job = Option.value job.Job.timezone ~default:fallback

type scheduled_job = { job : Job.t; fires : Ptime.t list }

let schedule_job ~timezone ~from ~until job =
  let timezone = job_timezone timezone job in
  let compiled = Schedule.compile ~timezone job.Job.expr in
  { job; fires = Schedule.within_compiled compiled ~from ~until }

let pairwise_conflicts ~threshold scheduled_jobs =
  let rec loop acc = function
    | [] | [ _ ] -> List.rev acc
    | scheduled :: rest ->
        let conflicts =
          List.concat_map
            (fun other ->
              Analysis.conflicts_between_fire_times
                ~expr_a:(Job.label scheduled.job) ~expr_b:(Job.label other.job)
                ~threshold scheduled.fires other.fires)
            rest
        in
        loop (List.rev_append conflicts acc) rest
  in
  loop [] scheduled_jobs

let overlaps_for_scheduled_jobs ~duration scheduled_jobs =
  List.concat_map
    (fun scheduled -> Analysis.overlaps_in_fire_times ~duration scheduled.fires)
    scheduled_jobs

let analyze ~timezone ~from ~until ~threshold ~duration jobs =
  let scheduled_jobs = List.map (schedule_job ~timezone ~from ~until) jobs in
  let warnings =
    List.map
      (fun job ->
        let timezone = job_timezone timezone job in
        (job, Analysis.warn ~timezone ~from job.Job.expr))
      jobs
  in
  let conflicts = pairwise_conflicts ~threshold scheduled_jobs in
  let overlaps =
    match duration with
    | None -> []
    | Some duration -> overlaps_for_scheduled_jobs ~duration scheduled_jobs
  in
  { jobs; warnings; conflicts; overlaps }

let analyze_with_policy ~timezone ~from ~until ~threshold ~duration ~policy jobs
    =
  let report = analyze ~timezone ~from ~until ~threshold ~duration jobs in
  let policy_violations = Policy.evaluate ~timezone ~from ~until policy jobs in
  { report; policy_violations }

let has_findings report =
  List.exists (fun (_, warnings) -> warnings <> []) report.warnings
  || report.conflicts <> [] || report.overlaps <> []

let has_policy_findings policy_report =
  has_findings policy_report.report || policy_report.policy_violations <> []
