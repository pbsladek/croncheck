# syntax=docker/dockerfile:1

ARG OCAML_BUILDER_IMAGE=ocaml/opam:debian-12-ocaml-4.14
ARG DHI_RUNTIME_IMAGE=dhi.io/debian-base:bookworm

FROM ${OCAML_BUILDER_IMAGE} AS build

WORKDIR /src

COPY --chown=opam:opam dune-project croncheck.opam ./
RUN opam install --yes --deps-only --with-test .

COPY --chown=opam:opam . .
RUN opam exec -- dune build --profile release bin/main.exe
RUN cp _build/default/bin/main.exe /tmp/croncheck

FROM ${DHI_RUNTIME_IMAGE} AS runtime

COPY --from=build /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=build /tmp/croncheck /usr/local/bin/croncheck

ENTRYPOINT ["croncheck"]
CMD ["--help"]
