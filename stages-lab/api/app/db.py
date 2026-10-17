"""Engine and session. The app connects as the restricted role, never as the
migration owner, which is the whole point of having two.
"""
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from .config import load

settings = load()

engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=5,
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def session():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
