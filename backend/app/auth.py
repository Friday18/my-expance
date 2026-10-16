"""Bearer-token auth.

Production (AUTH_MODE=firebase): the app sends a Firebase ID token; we verify its signature,
audience and expiry against Google's public keys.

Development (AUTH_MODE=dev): the bearer token itself is used as the user id, so you can run
the API and the app without a Firebase project. Never use dev mode on a public server.
"""

from functools import wraps

from flask import current_app, g, jsonify, request

from .services import get_or_create_user

_request_adapter = None


def _google_request():
    global _request_adapter
    if _request_adapter is None:
        import google.auth.transport.requests

        _request_adapter = google.auth.transport.requests.Request()
    return _request_adapter


def verify_firebase_token(token: str, project_id: str) -> dict:
    """Return the decoded claims or raise ValueError."""
    from google.oauth2 import id_token

    if not project_id:
        raise ValueError("FIREBASE_PROJECT_ID is not configured")
    claims = id_token.verify_firebase_token(token, _google_request(), audience=project_id)
    if not claims or claims.get("iss") != f"https://securetoken.google.com/{project_id}":
        raise ValueError("bad issuer")
    if not claims.get("sub"):
        raise ValueError("missing subject")
    return claims


def _unauthorized(message: str):
    resp = jsonify({"error": message})
    resp.status_code = 401
    resp.headers["WWW-Authenticate"] = "Bearer"
    return resp


def require_auth(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return _unauthorized("missing bearer token")
        token = header[7:].strip()
        if not token:
            return _unauthorized("missing bearer token")

        if current_app.config["AUTH_MODE"] == "dev":
            if len(token) > 128:
                return _unauthorized("dev token too long")
            uid, email = token, None
        else:
            try:
                claims = verify_firebase_token(token, current_app.config["FIREBASE_PROJECT_ID"])
            except Exception:  # noqa: BLE001 - any verification failure is a 401
                return _unauthorized("invalid or expired token")
            uid, email = claims["sub"], claims.get("email")

        g.user = get_or_create_user(uid, email)
        return view(*args, **kwargs)

    return wrapper
