type error = {
  line : int;
  message : string;
}

val parse_lines :
  ?system:bool -> source_path:string -> string list -> (Job.t list, error list) result

val parse_file : ?system:bool -> string -> (Job.t list, error list) result

