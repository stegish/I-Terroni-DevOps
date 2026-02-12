import time
import sqlite3
import os
from hashlib import md5
from datetime import datetime

from pyramid.config import Configurator
from pyramid.view import view_config
from pyramid.response import Response
from pyramid.httpexceptions import HTTPFound, HTTPNotFound, HTTPForbidden
from pyramid.session import SignedCookieSessionFactory
from pyramid.events import NewRequest, subscriber, BeforeRender
from wsgiref.simple_server import make_server
from werkzeug.security import check_password_hash, generate_password_hash

# Configuration
DATABASE = 'tmp/minitwit.db'
PER_PAGE = 30
SECRET_KEY = 'development key'

def connect_db():
    """Returns a new connection to the database."""
    return sqlite3.connect(DATABASE)

def query_db(request, query, args=(), one=False):
    """Queries the database and returns a list of dictionaries."""
    cur = request.db.execute(query, args)
    rv = [dict((cur.description[idx][0], value)
               for idx, value in enumerate(row)) for row in cur.fetchall()]
    return (rv[0] if rv else None) if one else rv

def get_user_id(request, username):
    """Look up the id for a username."""
    rv = query_db(request, 'select user_id from user where username = ?',
                  [username], one=True)
    return rv['user_id'] if rv else None

def format_datetime(timestamp):
    """Format a timestamp for display."""
    return datetime.utcfromtimestamp(timestamp).strftime('%Y-%m-%d @ %H:%M')

def gravatar_url(email, size=80):
    """Return the gravatar image for the given email address."""
    return 'http://www.gravatar.com/avatar/%s?d=identicon&s=%d' % \
        (md5(email.strip().lower().encode('utf-8')).hexdigest(), size)

@subscriber(NewRequest)
def init_request(event):
    """
    Opens the DB connection and loads the logged-in user.
    """
    request = event.request
    request.db = connect_db()
    def close_db(request):
        request.db.close()
    request.add_finished_callback(close_db)
    request.user = None
    if 'user_id' in request.session:
        request.user = query_db(request, 'select * from user where user_id = ?',
                                [request.session['user_id']], one=True)

@subscriber(BeforeRender)
def add_global_renderer_globals(event):
    """
    Injects variables into every template context.
    """
    request = event['request']
    def url_for(endpoint, **values):
        if endpoint == 'static':
            return '/static/' + values.get('filename', '')
        else:
            return request.route_url(endpoint, **values)

    event['user'] = request.user
    event['get_flashed_messages'] = lambda: request.session.pop_flash()
    event['url_for'] = url_for

@view_config(route_name='timeline', renderer='templates/timeline_refactor.html')
def timeline(request):
    """Shows a users timeline or redirects to public."""
    if not request.user:
        return HTTPFound(location=request.route_url('public_timeline'))
    
    messages = query_db(request, '''
        select message.*, user.* from message, user
        where message.flagged = 0 and message.author_id = user.user_id and (
            user.user_id = ? or
            user.user_id in (select whom_id from follower
                                    where who_id = ?))
        order by message.pub_date desc limit ?''',
        [request.session['user_id'], request.session['user_id'], PER_PAGE])
        
    return {'messages': messages}

@view_config(route_name='public_timeline', renderer='templates/timeline_refactor.html')
def public_timeline(request):
    """Displays the latest messages of all users."""
    messages = query_db(request, '''
        select message.*, user.* from message, user
        where message.flagged = 0 and message.author_id = user.user_id
        order by message.pub_date desc limit ?''', [PER_PAGE])
    return {'messages': messages}

@view_config(route_name='user_timeline', renderer='templates/timeline_refactor.html')
def user_timeline(request):
    """Displays a user's tweets."""
    username = request.matchdict['username']
    profile_user = query_db(request, 'select * from user where username = ?',
                            [username], one=True)
    if profile_user is None:
        return HTTPNotFound()
        
    followed = False
    if request.user:
        check = query_db(request, '''select 1 from follower where
            follower.who_id = ? and follower.whom_id = ?''',
            [request.session['user_id'], profile_user['user_id']], one=True)
        followed = check is not None
        
    messages = query_db(request, '''
            select message.*, user.* from message, user where
            user.user_id = message.author_id and user.user_id = ?
            order by message.pub_date desc limit ?''',
            [profile_user['user_id'], PER_PAGE])
            
    return {'messages': messages, 'followed': followed, 'profile_user': profile_user}

@view_config(route_name='follow_user')
def follow_user(request):
    """Adds the current user as follower of the given user."""
    if not request.user:
        return HTTPForbidden()
    
    username = request.matchdict['username']
    whom_id = get_user_id(request, username)
    if whom_id is None:
        return HTTPNotFound()
        
    request.db.execute('insert into follower (who_id, whom_id) values (?, ?)',
                       [request.session['user_id'], whom_id])
    request.db.commit()
    request.session.flash('You are now following "%s"' % username)
    return HTTPFound(location=request.route_url('user_timeline', username=username))

@view_config(route_name='unfollow_user')
def unfollow_user(request):
    """Removes the current user as follower of the given user."""
    if not request.user:
        return HTTPForbidden()
        
    username = request.matchdict['username']
    whom_id = get_user_id(request, username)
    if whom_id is None:
        return HTTPNotFound()
        
    request.db.execute('delete from follower where who_id=? and whom_id=?',
                       [request.session['user_id'], whom_id])
    request.db.commit()
    request.session.flash('You are no longer following "%s"' % username)
    return HTTPFound(location=request.route_url('user_timeline', username=username))

@view_config(route_name='add_message', request_method='POST')
def add_message(request):
    """Registers a new message for the user."""
    if 'user_id' not in request.session:
        return HTTPForbidden()
    
    text = request.POST.get('text')
    if text:
        request.db.execute('''insert into message (author_id, text, pub_date, flagged)
            values (?, ?, ?, 0)''', (request.session['user_id'], text,
                                  int(time.time())))
        request.db.commit()
        request.session.flash('Your message was recorded')
        
    return HTTPFound(location=request.route_url('timeline'))

@view_config(route_name='login', renderer='templates/login_refactor.html')
def login(request):
    """Logs the user in."""
    if request.user:
        return HTTPFound(location=request.route_url('timeline'))
        
    error = None
    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password')
        
        user = query_db(request, '''select * from user where
            username = ?''', [username], one=True)
            
        if user is None:
            error = 'Invalid username'
        elif not check_password_hash(user['pw_hash'], password):
            error = 'Invalid password'
        else:
            request.session['user_id'] = user['user_id']
            request.session.flash('You were logged in')
            return HTTPFound(location=request.route_url('timeline'))
            
    return {'error': error}

@view_config(route_name='register', renderer='templates/register_refactor.html')
def register(request):
    """Registers the user."""
    if request.user:
        return HTTPFound(location=request.route_url('timeline'))
        
    error = None
    if request.method == 'POST':
        username = request.POST.get('username')
        email = request.POST.get('email')
        password = request.POST.get('password')
        password_confirm = request.POST.get('password2')
        
        if not username:
            error = 'You have to enter a username'
        elif not email or '@' not in email:
            error = 'You have to enter a valid email address'
        elif not password:
            error = 'You have to enter a password'
        elif password != password_confirm:
            error = 'The two passwords do not match'
        elif get_user_id(request, username) is not None:
            error = 'The username is already taken'
        else:
            request.db.execute('''insert into user (
                username, email, pw_hash) values (?, ?, ?)''',
                [username, email, generate_password_hash(password)])
            request.db.commit()
            request.session.flash('You were successfully registered and can login now')
            return HTTPFound(location=request.route_url('login'))
            
    return {'error': error}

@view_config(route_name='logout')
def logout(request):
    """Logs the user out"""
    request.session.invalidate()
    request.session.flash('You were logged out')
    return HTTPFound(location=request.route_url('public_timeline'))

def init_db():
    """Helper to create the database tables (run manually if needed)."""
    with sqlite3.connect(DATABASE) as db:
        with open('schema.sql', 'rb') as f:
            db.cursor().executescript(f.read().decode('utf-8'))
        db.commit()

with Configurator() as config:
    config.include('pyramid_jinja2')
    config.add_jinja2_renderer('.html')
    config.add_jinja2_search_path('templates')
    config.commit()
    jinja_env = config.get_jinja2_environment(name='.html')
    jinja_env.filters['datetimeformat'] = format_datetime
    jinja_env.filters['gravatar'] = gravatar_url

    session_factory = SignedCookieSessionFactory(SECRET_KEY)
    config.set_session_factory(session_factory)

    config.add_static_view(name='static', path='static')
    
    config.add_route('timeline', '/')
    config.add_route('public_timeline', '/public')
    config.add_route('login', '/login')
    config.add_route('register', '/register')
    config.add_route('logout', '/logout')
    config.add_route('add_message', '/add_message')
    config.add_route('follow_user', '/{username}/follow')
    config.add_route('unfollow_user', '/{username}/unfollow')
    config.add_route('user_timeline', '/{username}')
    config.scan()

    app = config.make_wsgi_app()


if __name__ == '__main__':
    print("Running on http://0.0.0.0:5000")
    make_server('0.0.0.0', 5000, app).serve_forever()