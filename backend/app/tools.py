"""Tools the Claude agent can call. Every tool runs as the signed-in user passed in by the server;
no tool accepts a user id, so the model can never read or change another user's data."""

from datetime import date, timedelta

from . import services
from .models import CATEGORIES, User

_CATEGORY = {"type": "string", "enum": list(CATEGORIES)}
_DATE = {"type": "string", "description": "YYYY-MM-DD"}

TOOL_SCHEMAS = [
    {
        "name": "get_today",
        "description": "Get today's date, weekday and the user's currency. Call this before working out "
        "relative dates like 'yesterday' or 'last month'.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "add_expense",
        "description": "Log a new expense for the user.",
        "input_schema": {
            "type": "object",
            "properties": {
                "amount": {"type": "number", "description": "Positive amount in the user's currency"},
                "category": _CATEGORY,
                "note": {"type": "string", "description": "Short description, e.g. 'lunch at office'"},
                "spent_on": {**_DATE, "description": "Date spent, YYYY-MM-DD. Defaults to today."},
            },
            "required": ["amount", "category"],
        },
    },
    {
        "name": "update_expense",
        "description": "Change an existing expense. Use list_expenses first to find its id.",
        "input_schema": {
            "type": "object",
            "properties": {
                "id": {"type": "integer"},
                "amount": {"type": "number"},
                "category": _CATEGORY,
                "note": {"type": "string"},
                "spent_on": _DATE,
            },
            "required": ["id"],
        },
    },
    {
        "name": "delete_expense",
        "description": "Delete an expense by id. Only do this when the user clearly asks.",
        "input_schema": {"type": "object", "properties": {"id": {"type": "integer"}}, "required": ["id"]},
    },
    {
        "name": "list_expenses",
        "description": "List the user's expenses, newest first, optionally filtered by date range and category.",
        "input_schema": {
            "type": "object",
            "properties": {
                "start": _DATE,
                "end": _DATE,
                "category": _CATEGORY,
                "limit": {"type": "integer", "minimum": 1, "maximum": 100},
            },
        },
    },
    {
        "name": "spending_summary",
        "description": "Totals by category for a date range (defaults to the current month).",
        "input_schema": {"type": "object", "properties": {"start": _DATE, "end": _DATE}},
    },
    {
        "name": "budget_status",
        "description": "This month's budget, amount spent, remaining and a safe amount per day.",
        "input_schema": {"type": "object", "properties": {}},
    },
]


def _opt_date(value, field):
    return services.parse_date(value, field) if value else None


def execute_tool(name: str, args: dict, user: User, today: date | None = None) -> tuple[dict, dict | None]:
    """Run a tool. Returns (result for the model, action for the app or None).
    Raises services.ValidationError / NotFound for bad input; the agent reports those back to Claude."""
    today = today or date.today()
    args = args or {}

    if name == "get_today":
        return {
            "today": today.isoformat(),
            "weekday": today.strftime("%A"),
            "yesterday": (today - timedelta(days=1)).isoformat(),
            "currency": user.currency,
        }, None

    if name == "add_expense":
        e = services.add_expense(user.id, args, today=today)
        return {"ok": True, "expense": e.to_dict()}, {"type": "added", "expense": e.to_dict()}

    if name == "update_expense":
        fields = {k: args[k] for k in ("amount", "category", "note", "spent_on") if k in args}
        e = services.update_expense(user.id, int(args["id"]), fields)
        return {"ok": True, "expense": e.to_dict()}, {"type": "updated", "expense": e.to_dict()}

    if name == "delete_expense":
        e = services.get_expense(user.id, int(args["id"]))
        snapshot = e.to_dict()
        services.delete_expense(user.id, e.id)
        return {"ok": True, "deleted_id": snapshot["id"]}, {"type": "deleted", "expense": snapshot}

    if name == "list_expenses":
        items = services.list_expenses(
            user.id,
            start=_opt_date(args.get("start"), "start"),
            end=_opt_date(args.get("end"), "end"),
            category=args.get("category"),
            limit=min(int(args.get("limit", 30)), 100),
        )
        return {"expenses": [e.to_dict() for e in items], "count": len(items)}, None

    if name == "spending_summary":
        default_start, default_end = services.month_bounds(today)
        start = _opt_date(args.get("start"), "start") or default_start
        end = _opt_date(args.get("end"), "end") or default_end
        return services.summary(user.id, start, end), None

    if name == "budget_status":
        return services.budget_status(user, today), None

    raise services.ValidationError(f"unknown tool: {name}")
