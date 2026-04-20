type error = { line : int; message : string }

let trim = String.trim

let is_blank_or_comment line =
  let line = trim line in
  line = "" || String.starts_with ~prefix:"#" line

let is_env_assignment line =
  let line = trim line in
  match String.index_opt line '=' with
  | None -> false
  | Some eq ->
      let name = String.sub line 0 eq |> trim in
      let valid_name_char = function
        | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' -> true
        | _ -> false
      in
      name <> ""
      && (match name.[0] with
         | 'A' .. 'Z' | 'a' .. 'z' | '_' -> true
         | _ -> false)
      && String.for_all valid_name_char name

let words line = Util.split_words (trim line)

let take n xs =
  let rec loop acc n xs =
    if n = 0 then Some (List.rev acc, xs)
    else match xs with [] -> None | x :: xs -> loop (x :: acc) (n - 1) xs
  in
  loop [] n xs

let parse_line ~system ~source_path line_no line =
  if is_blank_or_comment line || is_env_assignment line then Ok None
  else
    let parts = words line in
    match parts with
    | macro :: command_parts when String.starts_with ~prefix:"@" macro -> (
        match Cron.macro_expansion (String.lowercase_ascii macro) with
        | None ->
            Error
              {
                line = line_no;
                message =
                  Cron.parse_error_to_string (InvalidSyntax ("macro", macro));
              }
        | Some expr_raw -> (
            let user, command_parts =
              if system then
                match command_parts with
                | user :: command_parts -> (Some user, command_parts)
                | [] -> (None, [])
              else (None, command_parts)
            in
            if command_parts = [] then
              Error { line = line_no; message = "missing crontab command" }
            else
              let command = String.concat " " command_parts in
              match
                Job.make ?id:user ~command ~line:line_no
                  ~source:(CrontabFile source_path) expr_raw
              with
              | Ok job -> Ok (Some job)
              | Error e ->
                  Error
                    { line = line_no; message = Cron.parse_error_to_string e }))
    | _ -> (
        match take 5 parts with
        | None ->
            Error
              {
                line = line_no;
                message = "not enough fields for a crontab entry";
              }
        | Some (expr_parts, rest) -> (
            let expr_raw = String.concat " " expr_parts in
            let user, command_parts =
              if system then
                match rest with
                | user :: command -> (Some user, command)
                | [] -> (None, [])
              else (None, rest)
            in
            if command_parts = [] then
              Error { line = line_no; message = "missing crontab command" }
            else
              let command = String.concat " " command_parts in
              match
                Job.make ?id:user ~command ~line:line_no
                  ~source:(CrontabFile source_path) expr_raw
              with
              | Ok job -> Ok (Some job)
              | Error e ->
                  Error
                    { line = line_no; message = Cron.parse_error_to_string e }))

let parse_lines ?(system = false) ~source_path lines =
  let jobs, errors =
    lines
    |> List.mapi (fun index line ->
           parse_line ~system ~source_path (index + 1) line)
    |> List.fold_left
         (fun (jobs, errors) -> function
           | Ok None -> (jobs, errors)
           | Ok (Some job) -> (job :: jobs, errors)
           | Error e -> (jobs, e :: errors))
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

let parse_file ?system path =
  parse_lines ?system ~source_path:path (read_lines path)
