type source = Cli | Stdin | CrontabFile of string | KubernetesYaml of string

type t = {
  id : string option;
  expr_raw : string;
  expr : Cron.expr;
  command : string option;
  source : source;
  line : int option;
  timezone : Timezone.t option;
}

let make ?id ?command ?line ?timezone ~source expr_raw =
  match Cron.parse expr_raw with
  | Ok expr -> Ok { id; expr_raw; expr; command; source; line; timezone }
  | Error e -> Error e

let source_to_string = function
  | Cli -> "cli"
  | Stdin -> "stdin"
  | CrontabFile path -> path
  | KubernetesYaml path -> path

let label job =
  match (job.id, job.line) with
  | Some id, Some line ->
      Printf.sprintf "%s:%d %s" (source_to_string job.source) line id
  | Some id, None -> id
  | None, Some line -> Printf.sprintf "%s:%d" (source_to_string job.source) line
  | None, None -> job.expr_raw
