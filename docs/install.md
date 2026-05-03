---
layout: default
render_with_liquid: false
---

# Installation

## GitHub release binaries

Download the tarball and checksum for your platform from the latest GitHub
release.

Release artifacts are built for:

- Linux x86_64: `croncheck-linux-x86_64.tar.gz`
- Linux arm64: `croncheck-linux-arm64.tar.gz`
- macOS x86_64: `croncheck-macos-x86_64.tar.gz`
- macOS arm64: `croncheck-macos-arm64.tar.gz`
- Windows x86_64: `croncheck-windows-x86_64.tar.gz`

Linux example:

```sh
curl -LO https://github.com/pbsladek/croncheck/releases/latest/download/croncheck-linux-x86_64.tar.gz
curl -LO https://github.com/pbsladek/croncheck/releases/latest/download/croncheck-linux-x86_64.tar.gz.sha256
sha256sum -c croncheck-linux-x86_64.tar.gz.sha256
tar -xzf croncheck-linux-x86_64.tar.gz
install -m 0755 croncheck-linux-x86_64 /usr/local/bin/croncheck
```

macOS example:

```sh
curl -LO https://github.com/pbsladek/croncheck/releases/latest/download/croncheck-macos-arm64.tar.gz
curl -LO https://github.com/pbsladek/croncheck/releases/latest/download/croncheck-macos-arm64.tar.gz.sha256
shasum -a 256 -c croncheck-macos-arm64.tar.gz.sha256
tar -xzf croncheck-macos-arm64.tar.gz
install -m 0755 croncheck-macos-arm64 /usr/local/bin/croncheck
```

Windows PowerShell example:

```powershell
curl.exe -LO https://github.com/pbsladek/croncheck/releases/latest/download/croncheck-windows-x86_64.tar.gz
curl.exe -LO https://github.com/pbsladek/croncheck/releases/latest/download/croncheck-windows-x86_64.tar.gz.sha256
tar -xzf croncheck-windows-x86_64.tar.gz
.\croncheck-windows-x86_64.exe --help
```

## Docker

The published Docker Hub image is `pwbsladek/croncheck` for `linux/amd64` and
`linux/arm64`.

```sh
docker run --rm pwbsladek/croncheck:latest explain "0 9 * * 1-5"
docker run --rm pwbsladek/croncheck:latest next "0 9 * * *" --tz America/New_York --count 3
```

The image runtime is based on Docker Hardened Images (DHI) Debian Base.

## Build from source

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
