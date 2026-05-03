let current =
  let raw = "%%VERSION%%" in
  if String.contains raw '%' then "dev" else raw
