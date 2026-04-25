type job_count = { job : Job.t; fires : int }
type bucket = { start : Ptime.t; fire_count : int; job_counts : job_count list }

type report = {
  timezone : Timezone.t;
  from : Ptime.t;
  until : Ptime.t;
  bucket_seconds : int;
  buckets : bucket list;
}

let job_timezone fallback job = Option.value job.Job.timezone ~default:fallback

let seconds_since from t =
  Ptime.diff t from |> Ptime.Span.to_int_s |> Option.value ~default:0

let add_seconds t seconds =
  match Ptime.add_span t (Ptime.Span.of_int_s seconds) with
  | Some t -> t
  | None -> invalid_arg "time bucket out of range"

let bucket_start ~from ~bucket_seconds t =
  let elapsed = max 0 (seconds_since from t) in
  add_seconds from (elapsed / bucket_seconds * bucket_seconds)

let add_fire map start job =
  let jobs =
    match Hashtbl.find_opt map start with None -> [] | Some jobs -> jobs
  in
  Hashtbl.replace map start (job :: jobs)

let job_counts jobs =
  let sorted =
    List.sort (fun a b -> String.compare (Job.label a) (Job.label b)) jobs
  in
  let rec loop acc current count = function
    | [] -> (
        match current with
        | None -> List.rev acc
        | Some job -> List.rev ({ job; fires = count } :: acc))
    | job :: rest -> (
        match current with
        | Some current when Job.label current = Job.label job ->
            loop acc (Some current) (count + 1) rest
        | Some current ->
            loop ({ job = current; fires = count } :: acc) (Some job) 1 rest
        | None -> loop acc (Some job) 1 rest)
  in
  loop [] None 0 sorted

let analyze ~timezone ~from ~until ~bucket_seconds jobs =
  if bucket_seconds <= 0 then invalid_arg "bucket_seconds must be positive";
  let map = Hashtbl.create 64 in
  List.iter
    (fun job ->
      let timezone = job_timezone timezone job in
      Schedule.within ~timezone job.Job.expr ~from ~until
      |> List.iter (fun fire ->
          add_fire map (bucket_start ~from ~bucket_seconds fire) job))
    jobs;
  let buckets =
    Hashtbl.to_seq map |> List.of_seq
    |> List.map (fun (start, jobs) ->
        { start; fire_count = List.length jobs; job_counts = job_counts jobs })
    |> List.sort (fun a b -> Ptime.compare a.start b.start)
  in
  { timezone; from; until; bucket_seconds; buckets }

let busiest ?(limit = 10) report =
  let rec take n = function
    | [] -> []
    | _ when n <= 0 -> []
    | x :: xs -> x :: take (n - 1) xs
  in
  report.buckets
  |> List.sort (fun a b ->
      let by_count = compare b.fire_count a.fire_count in
      if by_count <> 0 then by_count else Ptime.compare a.start b.start)
  |> take limit
