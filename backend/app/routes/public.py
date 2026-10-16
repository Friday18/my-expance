from flask import Blueprint, current_app, jsonify, render_template_string
from sqlalchemy import text

from ..extensions import db, limiter

bp = Blueprint("public", __name__)

_PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{ title }} · {{ app_name }}</title>
<style>
 body{font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;max-width:720px;
      margin:40px auto;padding:0 20px;color:#1d1b20;background:#fff}
 h1{font-size:1.6rem} h2{font-size:1.15rem;margin-top:2rem} a{color:#3b5bdb}
 @media (prefers-color-scheme:dark){body{background:#141218;color:#e6e0e9} a{color:#9db2ff}}
</style></head><body>
<h1>{{ title }}</h1>
{{ body|safe }}
<p style="margin-top:3rem;color:#777">{{ app_name }} · {{ developer }} · <a href="mailto:{{ email }}">{{ email }}</a></p>
</body></html>"""

_PRIVACY = """
<p>Last updated: 15 October 2026</p>
<p>{{ app_name }} is a personal expense tracker. This policy explains what data the app handles and why.</p>
<h2>What we collect</h2>
<ul>
 <li><b>Account:</b> your sign-in identifier and email address, from Google, Apple or email sign-in
   (handled by Firebase Authentication).</li>
 <li><b>Expenses you enter:</b> amount, category, note and date, and your monthly budget and currency.</li>
 <li><b>Assistant messages:</b> messages you send to the assistant are processed to log or look up expenses.
   They are not stored on our servers after the reply is sent.</li>
 <li><b>Crash reports:</b> technical crash data (device model, OS version, stack trace) via Firebase Crashlytics.</li>
</ul>
<h2>How we use it</h2>
<p>Only to provide the app: storing and showing your expenses, answering your questions about them, and fixing crashes.
We do not sell your data, show ads, or use your data for tracking.</p>
<h2>Service providers</h2>
<ul>
 <li>Google Firebase (sign-in, crash reports)</li>
 <li>Render (hosting and database)</li>
 <li>An AI model provider (such as Groq, Google or Anthropic), which processes assistant messages only to generate replies</li>
</ul>
<h2>Security</h2>
<p>All traffic is encrypted with HTTPS. Each request is checked against your sign-in token, and you can only access your own data.</p>
<h2>Deleting your data</h2>
<p>Delete your account any time in the app under <b>Settings → Delete account</b>. This permanently deletes your
account and all expenses. See <a href="/account-deletion">account deletion</a> for other options.</p>
<h2>Children</h2>
<p>The app is not directed at children under 13.</p>
<h2>Contact</h2>
<p>Questions: <a href="mailto:{{ email }}">{{ email }}</a></p>
"""

_DELETION = """
<p>You can delete your {{ app_name }} account and all of its data at any time.</p>
<h2>In the app</h2>
<ol><li>Open {{ app_name }} and go to <b>Settings</b>.</li>
<li>Tap <b>Delete account</b> and confirm.</li></ol>
<h2>By email</h2>
<p>If you can't open the app, email <a href="mailto:{{ email }}">{{ email }}</a> from the address you signed up with,
with the subject "Delete my account". We'll delete it within 7 days.</p>
<h2>What is deleted</h2>
<p>Your account record, all expenses, budget settings and assistant usage counters are permanently deleted.
Nothing is kept afterwards, except anonymous crash reports, which expire after 90 days.</p>
"""


def _render(title: str, body: str):
    cfg = current_app.config
    ctx = {"app_name": cfg["APP_NAME"], "email": cfg["SUPPORT_EMAIL"], "developer": cfg["DEVELOPER_NAME"]}
    return render_template_string(_PAGE, title=title, body=render_template_string(body, **ctx), **ctx)


@bp.get("/health")
@limiter.exempt
def health():
    try:
        db.session.execute(text("SELECT 1"))
        return jsonify({"status": "ok"})
    except Exception:  # noqa: BLE001
        current_app.logger.exception("health check failed")
        return jsonify({"status": "error", "database": "unreachable"}), 503


@bp.get("/privacy")
def privacy():
    return _render("Privacy policy", _PRIVACY)


@bp.get("/account-deletion")
def account_deletion():
    return _render("Delete your account", _DELETION)


@bp.get("/")
def index():
    return jsonify({"name": current_app.config["APP_NAME"], "status": "ok"})
