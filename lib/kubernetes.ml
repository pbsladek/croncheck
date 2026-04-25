type error = { file : string; line : int option; message : string }

type doc = {
  kind : string option;
  name : string option;
  namespace : string option;
  schedule : (string * int) option;
  timezone : (string * int) option;
}

type doc_result = Ignored | Job of Job.t | Doc_error of error

let empty_doc =
  {
    kind = None;
    name = None;
    namespace = None;
    schedule = None;
    timezone = None;
  }

let trim = String.trim

let strip_quotes s =
  let len = String.length s in
  if
    len >= 2
    && ((s.[0] = '"' && s.[len - 1] = '"')
       || (s.[0] = '\'' && s.[len - 1] = '\''))
  then String.sub s 1 (len - 2)
  else s

let indent line =
  let rec loop i =
    if i < String.length line && line.[i] = ' ' then loop (i + 1) else i
  in
  loop 0

let key_value line =
  match String.index_opt line ':' with
  | None -> None
  | Some idx ->
      let key = String.sub line 0 idx |> trim in
      let value =
        String.sub line (idx + 1) (String.length line - idx - 1)
        |> trim |> strip_quotes
      in
      Some (key, value)

let split_docs lines =
  let finish current docs =
    match List.rev current with [] -> docs | doc -> doc :: docs
  in
  let docs, current =
    lines
    |> List.mapi (fun i line -> (i + 1, line))
    |> List.fold_left
         (fun (docs, current) (line_no, line) ->
           if trim line = "---" then (finish current docs, [])
           else (docs, (line_no, line) :: current))
         ([], [])
  in
  List.rev (finish current docs)

let parse_doc lines =
  let section_for line =
    match (indent line, key_value line) with
    | 0, Some ("metadata", "") -> Some `Metadata
    | 0, Some ("spec", "") -> Some `Spec
    | 0, Some _ -> Some `Top
    | _ -> None
  in
  let rec loop section doc = function
    | [] -> doc
    | (line_no, raw) :: rest ->
        let line = trim raw in
        if line = "" || String.starts_with ~prefix:"#" line then
          loop section doc rest
        else
          let section = Option.value (section_for raw) ~default:section in
          let doc =
            match (section, key_value line) with
            | `Top, Some ("kind", value) -> { doc with kind = Some value }
            | `Metadata, Some ("name", value) -> { doc with name = Some value }
            | `Metadata, Some ("namespace", value) ->
                { doc with namespace = Some value }
            | `Spec, Some ("schedule", value) ->
                { doc with schedule = Some (value, line_no) }
            | `Spec, Some ("timeZone", value) ->
                { doc with timezone = Some (value, line_no) }
            | _ -> doc
          in
          loop section doc rest
  in
  loop `Top empty_doc lines

let job_of_doc source_path doc =
  match doc.kind with
  | Some "CronJob" -> (
      match doc.schedule with
      | None ->
          Doc_error
            {
              file = source_path;
              line = None;
              message = "CronJob is missing spec.schedule";
            }
      | Some (schedule, line) -> (
          let schedule_words = Util.split_words schedule in
          let result =
            let timezone =
              match doc.timezone with
              | None -> Ok None
              | Some (raw, timezone_line) ->
                  Timezone.parse raw
                  |> Result.map (fun tz -> Some tz)
                  |> Result.map_error (fun message ->
                      { file = source_path; line = Some timezone_line; message })
            in
            Result.bind timezone (fun timezone ->
                if
                  List.exists
                    (fun word ->
                      let word = String.uppercase_ascii word in
                      String.starts_with ~prefix:"TZ=" word
                      || String.starts_with ~prefix:"CRON_TZ=" word)
                    schedule_words
                then
                  Error
                    {
                      file = source_path;
                      line = Some line;
                      message =
                        "Kubernetes CronJob schedules must not contain TZ= or \
                         CRON_TZ=; use spec.timeZone instead";
                    }
                else
                  let id =
                    match (doc.namespace, doc.name) with
                    | Some ns, Some name -> Some (ns ^ "/" ^ name)
                    | None, Some name -> Some name
                    | _ -> None
                  in
                  match
                    Job.make ?id ?timezone ~line
                      ~source:(KubernetesYaml source_path) schedule
                  with
                  | Ok job -> Ok job
                  | Error e ->
                      Error
                        {
                          file = source_path;
                          line = Some line;
                          message = Cron.parse_error_to_string e;
                        })
          in
          match result with Ok job -> Job job | Error error -> Doc_error error))
  | _ -> Ignored

let parse_lines ~source_path lines =
  let jobs, errors =
    lines |> split_docs |> List.map parse_doc
    |> List.fold_left
         (fun (jobs, errors) doc ->
           match job_of_doc source_path doc with
           | Job job -> (job :: jobs, errors)
           | Ignored -> (jobs, errors)
           | Doc_error e -> (jobs, e :: errors))
         ([], [])
  in
  match errors with
  | [] -> Ok (List.rev jobs)
  | errors -> Error (List.rev errors)

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
  | lines -> parse_lines ~source_path:path lines
  | exception Sys_error message ->
      Error [ { file = path; line = None; message } ]
