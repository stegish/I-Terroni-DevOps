import os
import time

from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

from metrics import db_query_duration_seconds

DATABASE_URI = os.environ.get("DATABASE_URL", "")
engine = create_engine(DATABASE_URI, pool_size=10, max_overflow=20, pool_pre_ping=True, pool_recycle=3600)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


@event.listens_for(engine, "before_cursor_execute")
def _db_before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    context._query_start_time = time.perf_counter()


@event.listens_for(engine, "after_cursor_execute")
def _db_after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    start = getattr(context, "_query_start_time", None)
    if start is not None:
        db_query_duration_seconds.observe(time.perf_counter() - start)


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


if __name__ == "__main__":
    init_db()
