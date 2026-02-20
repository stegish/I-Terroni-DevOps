import time
from datetime import datetime
from pyramid.view import view_config
from pyramid.response import Response
from pyramid.httpexceptions import HTTPForbidden, HTTPNotFound
from werkzeug.security import generate_password_hash

from db import query_db, get_user_id

def require_simulator_auth(request):
    """checks if the request contains the authorization header"""
    auth_header = request.headers.get('Authorization')
    if auth_header != 'Basic c2ltdWxhdG9yOnN1cGVyX3NhZmUh':
        raise HTTPForbidden(json={'status': 403, 'error_msg': 'You are not authorized to use this resource!'})

#we need to store the latest variable on our database to handling the request from the API
def update_latest(request):
    """parses the (latest) query param and saves it to the database"""
    parsed_latest = request.GET.get('latest')
    if parsed_latest is not None:
        try:
            latest_val = int(parsed_latest)
            request.db.execute("CREATE TABLE IF NOT EXISTS latest_command (id INTEGER PRIMARY KEY, value INTEGER)")
            request.db.execute("DELETE FROM latest_command")
            request.db.execute("INSERT INTO latest_command (id, value) VALUES (1, ?)", [latest_val])
            request.db.commit()
        except ValueError:
            pass

def format_api_datetime(timestamp):
    """formats timestamps to match the Swagger ones"""
    return datetime.utcfromtimestamp(timestamp).strftime('%Y-%m-%d %H:%M:%S')

@view_config(route_name='api_latest', request_method='GET', renderer='json')
def get_latest(request):
    """returns the latest ID"""
    try:
        cur = request.db.execute("SELECT value FROM latest_command WHERE id = 1")
        row = cur.fetchone()
        latest = row[0] if row else -1
    except Exception:
        latest = -1
    return {'latest': latest}

@view_config(route_name='register', request_method='POST', header='Authorization', renderer='json')
def api_register(request):
    """register a new user via API"""
    update_latest(request)
    try:
        data = request.json_body
    except ValueError:
        return Response(json={'status': 400, 'error_msg': 'Invalid JSON'}, status=400)

    username = data.get('username')
    email = data.get('email')
    password = data.get('pwd')

    error = None
    if not username:
        error = 'You have to enter a username'
    elif not email or '@' not in email:
        error = 'You have to enter a valid email address'
    elif not password:
        error = 'You have to enter a password'
    elif get_user_id(request, username) is not None:
        error = 'The username is already taken'

    if error:
        return Response(json={'status': 400, 'error_msg': error}, status=400)

    request.db.execute('''insert into user (
        username, email, pw_hash) values (?, ?, ?)''',
        [username, email, generate_password_hash(password)])
    request.db.commit()
    return Response(status=204)

@view_config(route_name='api_msgs', request_method='GET', renderer='json')
def api_msgs(request):
    """get recent messages"""
    update_latest(request)
    require_simulator_auth(request)
    
    no = int(request.GET.get('no', 100))
    messages = query_db(request, '''
        select message.text, message.pub_date, user.username 
        from message, user
        where message.flagged = 0 and message.author_id = user.user_id
        order by message.pub_date desc limit ?''', [no])
        
    results = [{'content': msg['text'], 'pub_date': format_api_datetime(msg['pub_date']), 'user': msg['username']} for msg in messages]
    return results

@view_config(route_name='api_user_msgs', request_method='GET', renderer='json')
def api_user_msgs_get(request):
    """get messages for a specific user"""
    update_latest(request)
    require_simulator_auth(request)
    
    username = request.matchdict['username']
    user_id = get_user_id(request, username)
    if user_id is None:
        raise HTTPNotFound()
        
    no = int(request.GET.get('no', 100))
    messages = query_db(request, '''
        select message.text, message.pub_date, user.username 
        from message, user
        where message.flagged = 0 and user.user_id = message.author_id and user.user_id = ?
        order by message.pub_date desc limit ?''', [user_id, no])
        
    results = [{'content': msg['text'], 'pub_date': format_api_datetime(msg['pub_date']), 'user': msg['username']} for msg in messages]
    return results

@view_config(route_name='api_user_msgs', request_method='POST', renderer='json')
def api_user_msgs_post(request):
    """post a new message as a specific user"""
    update_latest(request)
    require_simulator_auth(request)
    
    username = request.matchdict['username']
    user_id = get_user_id(request, username)
    if user_id is None:
        raise HTTPNotFound()
        
    try:
        data = request.json_body
    except ValueError:
        return Response(json={'status': 400, 'error_msg': 'Invalid JSON'}, status=400)
        
    content = data.get('content')
    if content:
        request.db.execute('''insert into message (author_id, text, pub_date, flagged)
            values (?, ?, ?, 0)''', (user_id, content, int(time.time())))
        request.db.commit()
        
    return Response(status=204)

@view_config(route_name='api_follows', request_method='GET', renderer='json')
def api_follows_get(request):
    """get list of users followed by the given user"""
    update_latest(request)
    require_simulator_auth(request)
    
    username = request.matchdict['username']
    user_id = get_user_id(request, username)
    if user_id is None:
        raise HTTPNotFound()
        
    no = int(request.GET.get('no', 100))
    followers = query_db(request, '''
        select user.username from user
        inner join follower on follower.whom_id = user.user_id
        where follower.who_id = ?
        limit ?''', [user_id, no])
        
    return {'follows': [row['username'] for row in followers]}

@view_config(route_name='api_follows', request_method='POST', renderer='json')
def api_follows_post(request):
    """follow or unfollow a user"""
    update_latest(request)
    require_simulator_auth(request)
    
    username = request.matchdict['username']
    user_id = get_user_id(request, username)
    if user_id is None:
        raise HTTPNotFound()
        
    try:
        data = request.json_body
    except ValueError:
        return Response(json={'status': 400, 'error_msg': 'Invalid JSON'}, status=400)
        
    if 'follow' in data:
        whom_username = data['follow']
        whom_id = get_user_id(request, whom_username)
        if whom_id is None:
            raise HTTPNotFound()
            
        check = query_db(request, 'select 1 from follower where who_id = ? and whom_id = ?', [user_id, whom_id], one=True)
        if not check:
            request.db.execute('insert into follower (who_id, whom_id) values (?, ?)', [user_id, whom_id])
            request.db.commit()
            
    elif 'unfollow' in data:
        whom_username = data['unfollow']
        whom_id = get_user_id(request, whom_username)
        if whom_id is None:
            raise HTTPNotFound()
            
        request.db.execute('delete from follower where who_id=? and whom_id=?', [user_id, whom_id])
        request.db.commit()
        
    return Response(status=204)