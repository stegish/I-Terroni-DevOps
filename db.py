from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import os

DATABASE_URI = os.environ.get("DATABASE_URL", "sqlite:///tmp/minitwit.db")
engine = create_engine(
    DATABASE_URI,
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,
    pool_recycle=300,
)
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


init_db()
