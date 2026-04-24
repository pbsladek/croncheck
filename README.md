# croncheck

[![CI](https://github.com/pbsladek/croncheck/actions/workflows/ci.yml/badge.svg)](https://github.com/pbsladek/croncheck/actions/workflows/ci.yml)
[![Release](https://github.com/pbsladek/croncheck/actions/workflows/release.yml/badge.svg)](https://github.com/pbsladek/croncheck/actions/workflows/release.yml)

`croncheck` is a small offline CLI for static analysis of cron expressions.

It can:

- explain a cron expression in plain English
- print upcoming fire times, optionally with gap statistics
- warn about surprising schedules
- find conflicts between schedules
- find self-overlaps for long-running jobs
- read schedules from stdin, crontab files, or Kubernetes CronJob YAML

Times are UTC by default. Fixed offsets like `+02:00` and IANA timezone names
like `America/New_York` are supported with `--tz`.

## Install

### From GitHub Releases

Download the binary tarball and checksum for your platform from the latest
release.

Linux:

```sh
curl -LO https://github.com/pbsladek/croncheck/releases/latest/download/croncheck-linux-x86_64.tar.gz
curl -LO https://github.com/pbsladek/croncheck/releases/latest/download/croncheck-linux-x86_64.tar.gz.sha256
sha256sum -c croncheck-linux-x86_64.tar.gz.sha256
tar -xzf croncheck-linux-x86_64.tar.gz
./croncheck-linux-x86_64 --help
```

Install it somewhere on your `PATH`:

```sh
install -m 0755 croncheck-linux-x86_64 /usr/local/bin/croncheck
```

macOS:

```sh
curl -LO https://github.com/pbsladek/croncheck/releases/latest/download/croncheck-macos-arm64.tar.gz
curl -LO https://github.com/pbsladek/croncheck/releases/latest/download/croncheck-macos-arm64.tar.gz.sha256
shasum -a 256 -c croncheck-macos-arm64.tar.gz.sha256
tar -xzf croncheck-macos-arm64.tar.gz
./croncheck-macos-arm64 --help
install -m 0755 croncheck-macos-arm64 /usr/local/bin/croncheck
```

### From Source

Install dependencies and build:

```sh
make deps
make build
```

Run without installing:

```sh
make run ARGS='next "*/5 * * * *" --count 10'
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
croncheck explain "0 9 * * 1-5"
# at 9:00 AM on Monday through Friday

croncheck next "*/5 * * * *" --count 10
croncheck next "*/5 * * * *" --count 10 --time-format human
croncheck next "0 9 * * *" --tz America/New_York --time-format human
croncheck next "*/30 * * * *" --count 6 --gaps   # show min/max/avg interval
croncheck next "0 0 * * *" --from 2024-01-01      # pin start time

croncheck warn "0 0 31 * *"
croncheck conflicts "*/5 * * * *" "*/3 * * * *" --window 24h --threshold 0
croncheck overlaps "* * * * *" --window 60m --duration 120
```

Plain output uses RFC3339 timestamps by default. Use `--time-format human` for
readable timestamps such as `April 22 Wed 2026 at 6:20 AM UTC`. JSON output
always uses RFC3339.

Use `--from` (RFC3339 or `YYYY-MM-DD`) on `next`, `conflicts`, `overlaps`, and
`check` to pin the analysis start time instead of using the current clock.

Timezone support:

- CLI `--tz` accepts `UTC`, `Z`, fixed offsets, and IANA names.
- Crontab files support `CRON_TZ=America/New_York` for following jobs.
- Kubernetes CronJob YAML honors `.spec.timeZone`.
- DST spring-forward gaps are skipped.
- DST fall-back folds fire once for each real instant.

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
opam lint croncheck.opam
find lib bin test \( -name '*.ml' -o -name '*.mli' \) -print | xargs ocamlformat --check
```

Or use the Makefile:

```sh
make check
make integration-test
```

`make integration-test` runs dune cram tests (`test/integration/e2e.t`) against
the compiled CLI, covering exit codes, stdout/stderr behavior, JSON output,
stdin input, crontab files, and Kubernetes CronJob YAML.

## Release

Releases are tag-driven. From a clean working tree:

```sh
make release VERSION=v0.1.0
```

That command runs the full local check, creates an annotated tag, and pushes it.
The GitHub release workflow builds Linux and macOS binary tarballs, smoke-tests
the downloaded artifacts, and publishes matching SHA-256 checksum files:

```sh
sha256sum -c croncheck-linux-x86_64.tar.gz.sha256
shasum -a 256 -c croncheck-macos-arm64.tar.gz.sha256
```

GitHub Actions updates are tracked by Dependabot. SLSA/provenance metadata is
not enabled yet.
