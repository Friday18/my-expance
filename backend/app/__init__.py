import logging

from flask import Flask, jsonify
from flask_cors import CORS
from werkzeug.exceptions import HTTPException
from werkzeug.middleware.proxy_fix import ProxyFix

from .config import Config
from .extensions import db, limiter


def create_app(overrides: dict | None = None) -> Flask:
    app = Flask(__name__)
    app.config.from_object(Config)
    if overrides:
        app.config.update(overrides)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

    if app.config["SENTRY_DSN"]:
        import sentry_sdk

        sentry_sdk.init(dsn=app.config["SENTRY_DSN"], traces_sample_rate=0.0, send_default_pii=False)

    if app.config["AUTH_MODE"] not in ("firebase", "dev"):
        raise RuntimeError("AUTH_MODE must be 'firebase' or 'dev'")
    if app.config["AUTH_MODE"] == "dev":
        app.logger.warning("AUTH_MODE=dev: bearer tokens are trusted as user ids. Never use this in production.")

    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1)  # Render sits behind a proxy
    CORS(app, resources={r"/api/*": {"origins": app.config["CORS_ORIGINS"]}})
    db.init_app(app)
    limiter.init_app(app)

    from .routes.api import bp as api_bp
    from .routes.public import bp as public_bp

    app.register_blueprint(public_bp)
    app.register_blueprint(api_bp)

    @app.errorhandler(HTTPException)
    def _http_error(exc: HTTPException):
        return jsonify({"error": exc.description or exc.name}), exc.code

    @app.after_request
    def _security_headers(resp):
        resp.headers.setdefault("X-Content-Type-Options", "nosniff")
        resp.headers.setdefault("Referrer-Policy", "no-referrer")
        resp.headers.setdefault("X-Frame-Options", "DENY")
        return resp

    if app.config["SQLALCHEMY_DATABASE_URI"].startswith("sqlite"):
        # Local development convenience; production uses Alembic migrations.
        with app.app_context():
            from . import models  # noqa: F401

            db.create_all()

    return app
