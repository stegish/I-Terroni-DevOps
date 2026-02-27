import time
import sqlite3
import os
from hashlib import md5
from datetime import datetime

from pyramid.config import Configurator
from pyramid.view import view_config
from models import User, Message, Follower
from db import get_db_session, get_user_id
from pyramid.response import Response
from pyramid.httpexceptions import HTTPFound, HTTPNotFound, HTTPForbidden
from pyramid.session import SignedCookieSessionFactory
from pyramid.events import NewRequest, subscriber, BeforeRender
from wsgiref.simple_server import make_server
from werkzeug.security import check_password_hash, generate_password_hash

# Configuration
PER_PAGE = 30
SECRET_KEY = 'development key'

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
# SOSTITUISCI L'INTERO METODO init_request CON:
@subscriber(NewRequest)
def init_request(event):
    request = event.request
    request.db = get_db_session()
    def close_db(request):
        request.db.close()
    request.add_finished_callback(close_db)
    
    request.user = None
    if 'user_id' in request.session:
        user_obj = request.db.query(User).filter(User.user_id == request.session['user_id']).first()
        if user_obj:
            request.user = {'user_id': user_obj.user_id, 'username': user_obj.username, 'email': user_obj.email, 'pw_hash': user_obj.pw_hash}

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
    
    followed_subquery = request.db.query(Follower.whom_id).filter(Follower.who_id == request.session['user_id']).subquery()
    
    messages_query = request.db.query(Message, User).join(User, Message.author_id == User.user_id).filter(
        Message.flagged == 0,
        (User.user_id == request.session['user_id']) | (User.user_id.in_(followed_subquery))
    ).order_by(Message.pub_date.desc()).limit(PER_PAGE).all()
    
    messages = [{'message_id': m.message_id, 'author_id': m.author_id, 'text': m.text, 'pub_date': m.pub_date, 'flagged': m.flagged, 'user_id': u.user_id, 'username': u.username, 'email': u.email} for m, u in messages_query]        
    return {'messages': messages}

@view_config(route_name='public_timeline', renderer='templates/timeline_refactor.html')
def public_timeline(request):
    """Displays the latest messages of all users."""
    messages_query = request.db.query(Message, User).join(User, Message.author_id == User.user_id).filter(
        Message.flagged == 0
    ).order_by(Message.pub_date.desc()).limit(PER_PAGE).all()
    
    messages = [{'message_id': m.message_id, 'author_id': m.author_id, 'text': m.text, 'pub_date': m.pub_date, 'flagged': m.flagged, 'user_id': u.user_id, 'username': u.username, 'email': u.email} for m, u in messages_query]    
    return {'messages': messages}

@view_config(route_name='user_timeline', renderer='templates/timeline_refactor.html')
def user_timeline(request):
    """Displays a user's tweets."""
    username = request.matchdict['username']
    profile_user_obj = request.db.query(User).filter(User.username == username).first()
    if profile_user_obj is None:
        return HTTPNotFound()
    profile_user = {'user_id': profile_user_obj.user_id, 'username': profile_user_obj.username, 'email': profile_user_obj.email}
        
    followed = False
    if request.user:
        check = request.db.query(Follower).filter(Follower.who_id == request.session['user_id'], Follower.whom_id == profile_user['user_id']).first()
        followed = check is not None
        
    messages_query = request.db.query(Message, User).join(User, Message.author_id == User.user_id).filter(
        Message.flagged == 0, User.user_id == profile_user['user_id']
    ).order_by(Message.pub_date.desc()).limit(PER_PAGE).all()
    
    messages = [{'message_id': m.message_id, 'author_id': m.author_id, 'text': m.text, 'pub_date': m.pub_date, 'flagged': m.flagged, 'user_id': u.user_id, 'username': u.username, 'email': u.email} for m, u in messages_query]
            
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
        
    new_follower = Follower(who_id=request.session['user_id'], whom_id=whom_id)
    request.db.add(new_follower)
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
        
    follower = request.db.query(Follower).filter(Follower.who_id == request.session['user_id'], Follower.whom_id == whom_id).first()
    if follower:
        request.db.delete(follower)
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
        new_msg = Message(author_id=request.session['user_id'], text=text, pub_date=int(time.time()), flagged=0)
        request.db.add(new_msg)
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
        
        user = request.db.query(User).filter(User.username == username).first()
        if user is None:
            error = 'Invalid username'
        elif not check_password_hash(user.pw_hash, password):
            error = 'Invalid password'
        else:
            request.session['user_id'] = user.user_id
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
            new_user = User(username=username, email=email, pw_hash=generate_password_hash(password))
            request.db.add(new_user)
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
    config.add_route('api_latest', '/latest')
    config.add_route('api_msgs', '/msgs')
    config.add_route('api_user_msgs', '/msgs/{username}')
    config.add_route('api_follows', '/fllws/{username}')
    config.add_route('follow_user', '/{username}/follow')
    config.add_route('unfollow_user', '/{username}/unfollow')
    config.add_route('user_timeline', '/{username}')

    #pyramid scan both this file and the api.py
    config.scan()
    config.scan('api')

    app = config.make_wsgi_app()

if __name__ == '__main__':
    print("Running on http://0.0.0.0:5000")
    make_server('0.0.0.0', 5000, app).serve_forever()