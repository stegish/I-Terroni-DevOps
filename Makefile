init:
	python -c"from minitwit import init_db; init_db()"

build:
	gcc flag_tool.c -l sqlite3 -o flag_tool

clean:
	rm flag_tool

lint:
	pip install ruff
	ruff check .
	ruff format --check .

lint-fix:
	ruff check --fix .
	ruff format .

