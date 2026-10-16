import hashlib

from flask import request
from flask_limiter import Limiter
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


db = SQLAlchemy(model_class=Base)


def _rate_key() -> str:
    """Rate-limit per signed-in token when present, otherwise per client IP."""
    auth = request.headers.get("Authorization", "")
    if auth:
        return "tok:" + hashlib.sha256(auth.encode()).hexdigest()[:24]
    return "ip:" + (request.remote_addr or "unknown")


limiter = Limiter(key_func=_rate_key)
