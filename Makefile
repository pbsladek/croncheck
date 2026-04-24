.PHONY: all build test integration-test coverage opam-lint check fmt fmt-check clean deps install run release help

DUNE ?= dune
OPAM ?= opam
OCAMLFORMAT ?= ocamlformat

ML_SOURCES := $(shell find lib bin test \( -name '*.ml' -o -name '*.mli' \) -print)

all: build

build:
	$(DUNE) build

test:
	$(DUNE) test

integration-test:
	$(DUNE) test test/integration

coverage:
	$(DUNE) build --instrument-with bisect_ppx
	rm -f bisect*.coverage
	$(foreach exe,$(wildcard _build/default/test/test_*.exe),\
	  BISECT_FILE=$(CURDIR)/bisect $(exe) 2>/dev/null;)
	bisect-ppx-report html
	bisect-ppx-report summary

opam-lint:
	$(OPAM) lint croncheck.opam

check: build test integration-test opam-lint fmt-check

fmt:
	$(OCAMLFORMAT) --inplace $(ML_SOURCES)

fmt-check:
	$(OCAMLFORMAT) --check $(ML_SOURCES)

clean:
	$(DUNE) clean

deps:
	$(OPAM) pin add --yes --no-action --kind=path croncheck .
	$(OPAM) install --yes --deps-only --with-test croncheck

install:
	$(OPAM) install .

run:
	$(DUNE) exec croncheck -- $(ARGS)

release:
	@if [ -z "$(VERSION)" ]; then \
		printf '%s\n' 'usage: make release VERSION=v0.1.0'; \
		exit 2; \
	fi
	@case "$(VERSION)" in \
		v*) ;; \
		*) printf '%s\n' 'VERSION must start with v, for example v0.1.0'; exit 2 ;; \
	esac
	@if [ -n "$$(git status --porcelain)" ]; then \
		printf '%s\n' 'working tree must be clean before tagging a release'; \
		exit 2; \
	fi
	@if git rev-parse --verify "refs/tags/$(VERSION)" >/dev/null 2>&1; then \
		printf '%s\n' 'tag $(VERSION) already exists'; \
		exit 2; \
	fi
	$(MAKE) check
	git tag -a "$(VERSION)" -m "Release $(VERSION)"
	git push origin "$(VERSION)"

help:
	@printf '%s\n' \
		'Targets:' \
		'  make build      Build the project' \
		'  make test       Run the test suite' \
		'  make integration-test' \
		'                  Run end-to-end CLI integration tests' \
		'  make coverage   Run tests with instrumentation; open _coverage/index.html' \
		'  make opam-lint  Validate croncheck.opam' \
		'  make check      Build, test, and check formatting' \
		'  make fmt        Format OCaml sources' \
		'  make fmt-check  Check OCaml formatting' \
		'  make clean      Remove dune build artifacts' \
		'  make deps       Install opam dependencies' \
		'  make install    Install croncheck into the active opam switch' \
		'  make run        Run croncheck through dune; pass args with ARGS=...' \
		'  make release    Run checks, tag, and push; pass VERSION=v0.1.0'
