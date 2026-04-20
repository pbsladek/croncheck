# croncheck

`croncheck` is a small offline CLI for static analysis of cron expressions.

It can:

- print upcoming fire times
- warn about surprising schedules
- find conflicts between schedules
- find self-overlaps for long-running jobs
- read schedules from stdin, crontab files, or Kubernetes CronJob YAML

Times are UTC by default. Fixed offsets like `+02:00` are supported with `--tz`.

## Install

From source:

```sh
opam install . --deps-only --with-test
dune build
```

Run without installing:

```sh
dune exec croncheck -- next "*/5 * * * *" --count 10
```

Install into the active opam switch:

```sh
opam install .
```

Then run:

```sh
croncheck next "*/5 * * * *" --count 10
```

## Usage

```sh
croncheck next "*/5 * * * *" --count 10
croncheck warn "0 0 31 * *"
croncheck conflicts "*/5 * * * *" "*/3 * * * *" --window 24h --threshold 0
croncheck overlaps "* * * * *" --window 60m --duration 120
```

Analyze multiple schedules:

```sh
printf '%s\n' "0 0 * * *" "0 0 31 * *" | croncheck check
croncheck check --from-crontab /etc/crontab --system-crontab
croncheck check --from-k8s cronjobs.yaml --format json
```

Supported syntax:

- POSIX-style 5-field cron expressions
- numeric values, ranges, lists, and steps
- month and weekday names, such as `JAN` and `MON`
- Sunday as `0` or `7`
- recurring macros: `@hourly`, `@daily`, `@weekly`, `@monthly`, `@yearly`
- basic Quartz 6/7-field expressions with seconds, optional year, and `?`

`@reboot` is rejected because it is not a recurring static schedule.

## Exit Codes

- `0`: success, no findings
- `1`: warnings, conflicts, or overlaps found
- `2`: cron parse error
- `3`: usage error

## Development

```sh
dune build
dune test
find lib bin test \( -name '*.ml' -o -name '*.mli' \) -print | xargs ocamlformat --check
```
