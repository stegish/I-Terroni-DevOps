.PHONY: init build clean lint lint-fix format check test test-unit test-api test-ui all install-dev

PYTHON ?= python

init:
	$(PYTHON) -c "from db import init_db; init_db()"

build:
	gcc flag_tool.c -l sqlite3 -o flag_tool

clean:
	rm -f flag_tool

install-dev:
	$(PYTHON) -m pip install --upgrade pip
	$(PYTHON) -m pip install ruff codespell mypy pytest requests
	$(PYTHON) -m pip install -r requirements.txt

# Static analysis (quality gates)
lint:
	$(PYTHON) -m ruff check .
	$(PYTHON) -m ruff format --check .
	$(PYTHON) -m codespell

lint-fix:
	$(PYTHON) -m ruff check --fix .
	$(PYTHON) -m ruff format .

format: lint-fix

typecheck:
	$(PYTHON) -m mypy --ignore-missing-imports --install-types --non-interactive .

# Tests (require the app running on http://localhost:8080)
test-unit:
	$(PYTHON) -m pytest minitwit_tests_refactor.py -v

test-api:
	$(PYTHON) -m pytest minitwit_sim_api_test.py -v

test-ui:
	$(PYTHON) -m pytest test_itu_minitwit_ui.py -v

test:
	$(PYTHON) -m pytest -v

# Mirror of the CI quality gate, runnable locally
check: lint
	@echo "All static checks passed."

all: install-dev check
	@echo "Local CI mirror finished."
