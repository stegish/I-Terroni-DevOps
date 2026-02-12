#!/usr/bin/env bash

# Configuration
PYTHON_CMD="python3"
APP_MODULE="minitwit_refactor"
APP_FILE="${APP_MODULE}.py"
# The Python code uses a relative path 'tmp/minitwit.db', not the system '/tmp/'
DB_PATH="tmp/minitwit.db" 

if [ "$1" = "init" ]; then
    # Ensure the local tmp directory exists as required by the Python code
    mkdir -p tmp 

    if [ -f "$DB_PATH" ]; then 
        echo "Database already exists at $DB_PATH."
        exit 1
    fi
    echo "Initializing database..."
    # Imports init_db from the new refactored file
    $PYTHON_CMD -c "from $APP_MODULE import init_db; init_db()"

elif [ "$1" = "startprod" ]; then
     echo "Starting minitwit with production webserver..."
     # Note: See 'Important Note' below regarding the Python code structure for Gunicorn
     nohup gunicorn --workers 4 --timeout 120 --bind 0.0.0.0:5000 "${APP_MODULE}:app" > tmp/out.log 2>&1 &

elif [ "$1" = "start" ]; then
    echo "Starting minitwit..."
    # Runs the Python script directly (Development mode)
    nohup $PYTHON_CMD "$APP_FILE" > tmp/out.log 2>&1 &

elif [ "$1" = "stop" ]; then
    echo "Stopping minitwit..."
    # Kills processes matching the new filename
    pkill -f "$APP_MODULE"

elif [ "$1" = "inspectdb" ]; then
    ./flag_tool -i | less

elif [ "$1" = "flag" ]; then
    ./flag_tool "$@"

else
  echo "I do not know this command..."
fi