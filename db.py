from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

DATABASE_URI = 'sqlite:///tmp/minitwit.db'
engine = create_engine(DATABASE_URI, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db_session():
    """return the new database session"""
    return SessionLocal()

def get_user_id(request, username):
    """search the id of a user"""
    from models import User
    user = request.db.query(User).filter(User.username == username).first()
    return user.user_id if user else None

def init_db():
    """initialize the db tables"""
    from models import Base
    Base.metadata.create_all(bind=engine)