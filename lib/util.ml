let month_name = function
  | 1 -> "January"
  | 2 -> "February"
  | 3 -> "March"
  | 4 -> "April"
  | 5 -> "May"
  | 6 -> "June"
  | 7 -> "July"
  | 8 -> "August"
  | 9 -> "September"
  | 10 -> "October"
  | 11 -> "November"
  | 12 -> "December"
  | _ -> "?"

let split_words s =
  let is_space = function ' ' | '\t' | '\n' | '\r' -> true | _ -> false in
  let len = String.length s in
  let rec skip i = if i < len && is_space s.[i] then skip (i + 1) else i in
  let rec take start i acc =
    if i = len then List.rev (String.sub s start (i - start) :: acc)
    else if is_space s.[i] then loop i (String.sub s start (i - start) :: acc)
    else take start (i + 1) acc
  and loop i acc =
    let i = skip i in
    if i = len then List.rev acc else take i i acc
  in
  loop 0 []
