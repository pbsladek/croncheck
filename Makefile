.PHONY: all build test check fmt fmt-check clean deps install run help

DUNE ?= dune
OPAM ?= opam
OCAMLFORMAT ?= ocamlformat

ML_SOURCES := $(shell find lib bin test \( -name '*.ml' -o -name '*.mli' \) -print)

all: build

build:
	$(DUNE) build

test:
	$(DUNE) test

check: build test fmt-check

fmt:
	$(OCAMLFORMAT) --inplace $(ML_SOURCES)

fmt-check:
	$(OCAMLFORMAT) --check $(ML_SOURCES)

clean:
	$(DUNE) clean

deps:
	$(OPAM) install . --deps-only --with-test

install:
	$(OPAM) install .

run:
	$(DUNE) exec croncheck -- $(ARGS)

help:
	@printf '%s\n' \
		'Targets:' \
		'  make build      Build the project' \
		'  make test       Run the test suite' \
		'  make check      Build, test, and check formatting' \
		'  make fmt        Format OCaml sources' \
		'  make fmt-check  Check OCaml formatting' \
		'  make clean      Remove dune build artifacts' \
		'  make deps       Install opam dependencies' \
		'  make install    Install croncheck into the active opam switch' \
		'  make run        Run croncheck through dune; pass args with ARGS=...'
