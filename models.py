from sqlalchemy import Column, ForeignKey, Integer, String
from sqlalchemy.orm import declarative_base

Base = declarative_base()


class User(Base):
    __tablename__ = "user"
    user_id = Column(Integer, primary_key=True, autoincrement=True)
    username = Column(String(255), nullable=False, unique=True)
    email = Column(String(255), nullable=False)
    pw_hash = Column(String(255), nullable=False)


class Follower(Base):
    __tablename__ = "follower"
    who_id = Column(Integer, ForeignKey("user.user_id"), primary_key=True)
    whom_id = Column(Integer, ForeignKey("user.user_id"), primary_key=True)


class Message(Base):
    __tablename__ = "message"
    message_id = Column(Integer, primary_key=True, autoincrement=True)
    author_id = Column(Integer, ForeignKey("user.user_id"), nullable=False)
    text = Column(String(255), nullable=False)
    pub_date = Column(Integer)
    flagged = Column(Integer, default=0)


class LatestCommand(Base):
    __tablename__ = "latest_command"
    id = Column(Integer, primary_key=True)
    value = Column(Integer)
