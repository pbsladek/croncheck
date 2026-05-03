---
layout: default
render_with_liquid: false
---

# Release and container design

This document records the intended release packaging behavior for binaries,
Docker images, and GitHub automation.

## Release trigger

The release workflow runs on pushed tags matching `v*`. `make release` is the
local entrypoint for creating those tags after running project checks.

`make release VERSION=v0.1.0` should:

1. require a version starting with `v`;
2. require a clean working tree;
3. reject existing tags;
4. run `make check`;
5. create an annotated tag;
6. push the tag.

## Native artifacts

GitHub release artifacts are built for:

- Linux x86_64;
- Linux arm64;
- macOS x86_64;
- macOS arm64;
- Windows x86_64.

Windows arm64 is intentionally excluded until `ocaml/setup-ocaml` and opam
support that combination reliably.

Each artifact is packaged as a `.tar.gz` with a matching SHA256 checksum. The
workflow smoke tests the built binary, uploads the archive, downloads it again,
verifies the checksum, extracts it, and smoke tests the extracted binary.

## Docker image

The Dockerfile uses a multi-stage build:

- OCaml/opam builder image for compilation.
- DHI Debian base runtime image for the final image.

The runtime image copies:

- `/usr/local/bin/croncheck`;
- `/usr/share/zoneinfo` from the builder.

Zoneinfo is included so IANA timezone support works inside the container.

## Multi-arch container publishing

The release workflow publishes Docker images for:

- `linux/amd64`;
- `linux/arm64`.

Docker publishing uses Buildx and QEMU. Images are pushed to Docker Hub as
`pwbsladek/croncheck` and tagged from the Git tag metadata.

## Registry credentials

The workflow uses:

- `DOCKERHUB_USERNAME`;
- `DOCKERHUB_TOKEN`.

Those credentials are used for Docker Hub login and DHI registry login in the
current setup.

## Supply-chain metadata

Docker builds enable:

- provenance;
- SBOM generation.

Actions are pinned by commit SHA in release and pages workflows. New workflow
steps should keep that convention unless there is a deliberate reason to change
it.

