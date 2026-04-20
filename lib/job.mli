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

val make :
  ?id:string ->
  ?command:string ->
  ?line:int ->
  ?timezone:Timezone.t ->
  source:source ->
  string ->
  (t, Cron.parse_error) result

val source_to_string : source -> string
val label : t -> string
