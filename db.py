import sqlite3

DATABASE = 'tmp/minitwit.db'

def connect_db():
    """returns a new connection to the database"""
    return sqlite3.connect(DATABASE)

def query_db(request, query, args=(), one=False):
    """queries the database, returns a list of dictionaries"""
    cur = request.db.execute(query, args)
    rv = [dict((cur.description[idx][0], value)
               for idx, value in enumerate(row)) for row in cur.fetchall()]
    return (rv[0] if rv else None) if one else rv

def get_user_id(request, username):
    """look up the id for a username"""
    rv = query_db(request, 'select user_id from user where username = ?',
                  [username], one=True)
    return rv['user_id'] if rv else None

def init_db():
    """helper to create the database tables"""
    with connect_db() as db:
        with open('schema.sql', 'rb') as f:
            db.cursor().executescript(f.read().decode('utf-8'))
        db.commit()