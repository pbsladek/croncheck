type error = {
  file : string;
  line : int option;
  message : string;
}

val parse_lines : source_path:string -> string list -> (Job.t list, error list) result
val parse_file : string -> (Job.t list, error list) result

