# Common tasks for this repository. `make` on its own runs everything CI runs.
#
#   make check      - static checks and regression tests (what CI runs)
#   make install    - link the live mod folder to this checkout
#   make archive    - archive the last match's bot output
#   make parse      - read the newest archived run back as a table
PYTHON ?= python3

# The newest archive wins, so `make parse` needs no arguments.
LOG ?= $(shell ls -t runs/*.log 2>/dev/null | head -1)

.PHONY: all check lint test install archive parse

all: check

# The static checks need no game install; they use it for symbol checks when present.
lint:
	@$(PYTHON) scripts/validate_personalities.py
	@$(PYTHON) scripts/check_xs.py

test:
	@$(PYTHON) scripts/tests/test_check_xs.py
	@$(PYTHON) scripts/tests/test_archive_run.py

check: lint test

install:
	@./scripts/install.sh

archive:
	@$(PYTHON) scripts/archive_run.py

parse:
	@test -n "$(LOG)" || { echo "no archives in runs/ - run 'make archive' after a match" >&2; exit 1; }
	@$(PYTHON) scripts/parse_ai_log.py $(LOG)
