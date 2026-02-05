if [ "$1" = "init" ]; then  #REFACTORING "$1"

    if [ -f "/tmp/minitwit.db" ]; then 
        echo "Database already exists."
        exit 1
    fi
    echo "Putting a database to /tmp/minitwit.db..."
    python -c"from minitwit import init_db;init_db()"
elif [ "$1" = "startprod" ]; then   #REFACTORING "$1"
     echo "Starting minitwit with production webserver..."
     nohup "$HOME"/.local/bin/gunicorn --workers 4 --timeout 120 --bind 0.0.0.0:5000 minitwit:app > /tmp/out.log 2>&1 & #REFACTORING "$HOME"
elif [ "$1" = "start" ]; then   #REFACTORING "$1"
    echo "Starting minitwit..."
    nohup $(which python) minitwit.py > /tmp/out.log 2>&1 & #REFACTORING $()
elif [ "$1" = "stop" ]; then    #REFACTORING "$1"
    echo "Stopping minitwit..."
    pkill -f minitwit
elif [ "$1" = "inspectdb" ]; then   #REFACTORING "$1"
    ./flag_tool -i | less
elif [ "$1" = "flag" ]; then    #REFACTORING "$1"
    ./flag_tool "$@"
else
  echo "I do not know this command..."
fi
