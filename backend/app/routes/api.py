from datetime import date

from flask import Blueprint, current_app, g, jsonify, request

from .. import services
from ..agent import AgentBusy, AgentError, run_agent
from ..auth import require_auth
from ..extensions import db, limiter
from ..models import CATEGORIES, ChatUsage

bp = Blueprint("api", __name__, url_prefix="/api")


def _json_body() -> dict:
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise services.ValidationError("request body must be a JSON object")
    return data


@bp.errorhandler(services.ValidationError)
def _validation(exc):
    return jsonify({"error": str(exc)}), 400


@bp.errorhandler(services.NotFound)
def _not_found(exc):
    return jsonify({"error": str(exc)}), 404


# ---------- profile ----------

@bp.get("/me")
@require_auth
def me():
    return jsonify({**g.user.to_dict(), "categories": list(CATEGORIES)})


@bp.patch("/me")
@require_auth
def update_me():
    user = services.update_user(g.user, _json_body())
    return jsonify(user.to_dict())


@bp.delete("/me")
@require_auth
def delete_me():
    services.delete_user(g.user)
    return "", 204


# ---------- expenses ----------

@bp.get("/expenses")
@require_auth
def list_expenses():
    args = request.args
    start = services.parse_date(args["start"], "start") if args.get("start") else None
    end = services.parse_date(args["end"], "end") if args.get("end") else None
    try:
        limit = int(args.get("limit", 500))
    except ValueError:
        raise services.ValidationError("limit must be a number") from None
    items = services.list_expenses(g.user.id, start, end, args.get("category") or None, limit)
    return jsonify({"expenses": [e.to_dict() for e in items]})


@bp.post("/expenses")
@require_auth
def create_expense():
    expense = services.add_expense(g.user.id, _json_body())
    return jsonify(expense.to_dict()), 201


@bp.patch("/expenses/<int:expense_id>")
@require_auth
def update_expense(expense_id: int):
    expense = services.update_expense(g.user.id, expense_id, _json_body())
    return jsonify(expense.to_dict())


@bp.delete("/expenses/<int:expense_id>")
@require_auth
def delete_expense(expense_id: int):
    services.delete_expense(g.user.id, expense_id)
    return "", 204


@bp.get("/summary")
@require_auth
def summary():
    today = date.today()
    default_start, default_end = services.month_bounds(today)
    start = services.parse_date(request.args["start"], "start") if request.args.get("start") else default_start
    end = services.parse_date(request.args["end"], "end") if request.args.get("end") else default_end
    data = services.summary(g.user.id, start, end)
    data["budget"] = services.budget_status(g.user, today)
    return jsonify(data)


# ---------- assistant ----------

def _validate_messages(raw) -> list[dict]:
    cfg = current_app.config
    if not isinstance(raw, list) or not raw:
        raise services.ValidationError("messages must be a non-empty list")
    raw = raw[-cfg["CHAT_MAX_MESSAGES"]:]
    out = []
    for m in raw:
        if not isinstance(m, dict) or m.get("role") not in ("user", "assistant"):
            raise services.ValidationError("each message needs role 'user' or 'assistant'")
        content = m.get("content")
        if not isinstance(content, str) or not content.strip():
            raise services.ValidationError("each message needs text content")
        if len(content) > cfg["CHAT_MAX_CHARS"]:
            raise services.ValidationError(f"messages must be under {cfg['CHAT_MAX_CHARS']} characters")
        out.append({"role": m["role"], "content": content})
    # The API needs the conversation to start with the user and end with the user.
    while out and out[0]["role"] != "user":
        out.pop(0)
    if not out or out[-1]["role"] != "user":
        raise services.ValidationError("the last message must be from the user")
    return out


def _take_quota(user_id: str) -> bool:
    today = date.today()
    usage = db.session.get(ChatUsage, (user_id, today))
    if usage is None:
        usage = ChatUsage(user_id=user_id, day=today, count=0)
        db.session.add(usage)
    if usage.count >= current_app.config["CHAT_DAILY_LIMIT"]:
        return False
    usage.count += 1
    db.session.commit()
    return True


@bp.post("/chat")
@limiter.limit("15 per minute")
@require_auth
def chat():
    messages = _validate_messages(_json_body().get("messages"))
    if not _take_quota(g.user.id):
        return jsonify({"error": "You've reached today's assistant limit. It resets at midnight."}), 429
    try:
        result = run_agent(messages, g.user)
    except AgentBusy:
        current_app.logger.warning("model provider rate limit hit")
        return jsonify({"error": "The assistant is busy right now. Please try again in a minute."}), 429
    except AgentError as exc:
        current_app.logger.error("agent not configured: %s", exc)
        return jsonify({"error": "The assistant is not available right now."}), 503
    except Exception:  # noqa: BLE001 - upstream API errors
        current_app.logger.exception("agent failed")
        return jsonify({"error": "The assistant had a problem. Please try again."}), 502
    return jsonify(result)
