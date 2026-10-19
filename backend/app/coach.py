"""The monthly money coach: reviews one month and returns a strict JSON plan (one win + up to 3 suggestions).

Pipeline (see the Learning Notes, Step 2):
1. Too little history (under 21 days) -> a fixed message, no model call.
2. Python computes the facts; the model reads them and may call 6 read-only tools for more.
3. The model's answer is parsed as JSON and validated: shape, allowed actions, number grounding (every number
   in the win and the reasons must appear in a fact or tool result) and a guardrail against investment advice.
4. Any problem -> the exact errors go back to the model once; still failing -> a safe fallback report.
5. The server, not the model, adds the disclaimer.
"""

import json
import re
from datetime import date, datetime, timezone

from . import insights, services
from .insights import Txn
from .llm import TooManySteps, run_tool_loop, tool_error
from .models import CATEGORIES, User

MIN_HISTORY_DAYS = 21
MAX_SUGGESTIONS = 3
DISCLAIMER = "This is a budgeting suggestion based on your own spending, not financial advice."
NOT_ENOUGH_DATA = (
    "Keep logging for a few more weeks. The coach needs at least 3 weeks of expenses to give useful advice."
)

CURRENCY_SYMBOLS = {"INR": "₹", "USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥"}

_MONTH = {"type": "string", "description": "YYYY-MM. Defaults to the review month."}

COACH_TOOLS = [
    {
        "name": "month_summary",
        "description": "One month's total, categories with share %, daily average, weekend share %, "
        "small spends and the biggest expense.",
        "input_schema": {"type": "object", "properties": {"month": _MONTH}},
    },
    {
        "name": "compare_months",
        "description": "A month against the average of the months before it: totals, differences and "
        "% change, overall and per category.",
        "input_schema": {
            "type": "object",
            "properties": {"month": _MONTH, "n": {"type": "integer", "minimum": 2, "maximum": 6,
                                                  "description": "Months to include, default 4"}},
        },
    },
    {
        "name": "category_trend",
        "description": "One category over the last 6 months, its previous average and % change.",
        "input_schema": {
            "type": "object",
            "properties": {"category": {"type": "string", "enum": list(CATEGORIES)}},
            "required": ["category"],
        },
    },
    {
        "name": "recurring_payments",
        "description": "Payments that repeat with a similar amount (subscriptions, bills) in the last 3 months.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "budget_status",
        "description": "This month's overall and per-category budgets: spent, remaining, pace and projection.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "goals_status",
        "description": "Each savings goal: target, saved, % done, months left and the monthly amount needed.",
        "input_schema": {"type": "object", "properties": {}},
    },
]

ACTION_TYPES = ("set_category_budget", "create_goal", "review_subscription")

SYSTEM_PROMPT = """You are the monthly money coach inside My Expance, a personal expense tracker.
You review one month of the user's spending and give a short, encouraging plan for next month.
Review month: __MONTH_NAME__ (__MONTH__). Today: __TODAY__. Currency: __CURRENCY__, written like __MONEY__.

The first message holds the facts for the review month. Call the tools for more detail when useful
(category_trend, recurring_payments, budget_status, goals_status).

Rules:
- Every number you write must be copied exactly from the facts or a tool result. Never calculate, estimate
  or round a number yourself: the tools already give totals, averages, differences and percentages.
- Start with one genuine win.
- Give 1 to 3 suggestions. Each has one clear action.
- Budgeting and spending habits only. Never mention investing, stocks, mutual funds, SIPs, crypto, loans or
  insurance.
- Be kind and encouraging, never shaming. Keep each text short.

Reply with JSON only, no other text, in exactly this shape:
{
  "win": "one sentence about something that went well",
  "suggestions": [
    {
      "title": "short imperative, e.g. Cap food delivery at __MONEY__",
      "why": "one sentence with the numbers behind it",
      "action": {"type": "set_category_budget", "category": "food", "amount": 4000},
      "est_monthly_saving": 1250
    }
  ],
  "next_month_budget": 30000
}

Action types:
- {"type": "set_category_budget", "category": one of __CATEGORIES__, "amount": number}
- {"type": "create_goal", "name": "short name", "target_amount": number, "target_date": "YYYY-MM-DD" (optional)}
- {"type": "review_subscription", "note": "the payment's note from recurring_payments"}
"est_monthly_saving" and "next_month_budget" are optional."""


class CoachError(RuntimeError):
    pass


# ---------------------------------------------------------------- formatting

def _group_indian(digits: str) -> str:
    if len(digits) <= 3:
        return digits
    head, tail = digits[:-3], digits[-3:]
    parts = []
    while len(head) > 2:
        parts.insert(0, head[-2:])
        head = head[:-2]
    if head:
        parts.insert(0, head)
    return ",".join(parts) + "," + tail


def fmt_money(amount: float, currency: str = "INR") -> str:
    """₹1,25,000 for INR (Indian grouping), $1,250 otherwise. Whole units only."""
    whole = str(int(round(abs(amount))))
    grouped = _group_indian(whole) if currency == "INR" else f"{int(whole):,}"
    symbol = CURRENCY_SYMBOLS.get(currency)
    sign = "-" if amount < 0 else ""
    return f"{sign}{symbol}{grouped}" if symbol else f"{sign}{currency} {grouped}"


def month_name(key: str) -> str:
    start, _ = insights.month_bounds(key)
    return start.strftime("%B %Y")


# ---------------------------------------------------------------- tools (read-only)

class CoachTools:
    """Runs the 6 coach tools for one signed-in user. Nothing here writes to the database."""

    def __init__(self, user: User, review_month: str, today: date):
        self.user = user
        self.review_month = review_month
        self.today = today
        self.earliest_month = insights.shift_month(review_month, -6)
        start, _ = insights.month_bounds(self.earliest_month)
        self.txns = [
            Txn(float(e.amount), e.category, e.note or "", e.spent_on)
            for e in services.expenses_between(user.id, start, today)
        ]
        self.outputs: list[dict] = []  # every result the model has seen, for number grounding

    def _month_arg(self, args: dict) -> str:
        key = args.get("month") or self.review_month
        insights.parse_month(key)
        if not (self.earliest_month <= key <= insights.month_key(self.today)):
            raise services.ValidationError(
                f"month must be between {self.earliest_month} and {insights.month_key(self.today)}"
            )
        return key

    def call(self, name: str, args: dict) -> dict:
        args = args or {}
        if name == "month_summary":
            result = insights.month_summary(self.txns, self._month_arg(args), self.today)
        elif name == "compare_months":
            result = insights.compare_months(self.txns, self._month_arg(args), int(args.get("n") or 4))
        elif name == "category_trend":
            result = insights.category_trend(
                self.txns, services.parse_category(args.get("category")), self.review_month
            )
        elif name == "recurring_payments":
            result = insights.recurring_payments(self.txns, self.review_month)
        elif name == "budget_status":
            result = self._budget_status()
        elif name == "goals_status":
            goals = services.list_goals(self.user.id)
            result = {"goals": [
                insights.goal_status(g.name, float(g.target_amount), float(g.saved_amount), g.target_date,
                                     self.today)
                for g in goals
            ]}
        else:
            raise services.ValidationError(f"unknown tool: {name}")
        self.outputs.append(result)
        return result

    def _budget_status(self) -> dict:
        this_month = [t for t in self.txns if insights.month_key(t.spent_on) == insights.month_key(self.today)]
        spent = sum(t.amount for t in this_month)
        overall = None
        if self.user.monthly_budget is not None:
            overall = insights.budget_pace(float(self.user.monthly_budget), spent, self.today)
        categories = []
        for cb in services.list_category_budgets(self.user.id):
            cat_spent = sum(t.amount for t in this_month if t.category == cb.category)
            categories.append({"category": cb.category,
                               **insights.budget_pace(float(cb.amount), cat_spent, self.today)})
        return {"month": insights.month_key(self.today), "overall": overall, "categories": categories}

    def executor(self, name: str, args) -> tuple[str, bool]:
        try:
            if not isinstance(args, dict):
                raise services.ValidationError("tool arguments must be an object")
            return json.dumps(self.call(name, args)), False
        except (services.ValidationError, KeyError, TypeError, ValueError) as exc:
            return tool_error(exc), True


# ---------------------------------------------------------------- number grounding

_NUMBER = re.compile(r"(?<![\w.])(\d[\d,]*)(?:\.(\d+))?(?:\s*(k|K|L|lakh|Cr|crore)\b)?")
_YEAR = re.compile(r"^(19|20|21)\d\d$")
_MULTIPLIERS = {"k": 1e3, "K": 1e3, "L": 1e5, "lakh": 1e5, "Cr": 1e7, "crore": 1e7}
IGNORE_SMALL_INTEGERS = 12  # "3-month average", "2 subscriptions": counts this small are not checked


def extract_numbers(text: str) -> list[tuple[float, float]]:
    """Numbers written in text, as (value, tolerance). Handles ₹1,25,000, 1,250.50, 38%, 2.1×, ₹1.2k, ₹3.4L.
    The tolerance is half of the last written digit, so "38%" matches 38.2 and "₹1.2k" matches 1,180."""
    found = []
    for m in _NUMBER.finditer(text):
        whole, frac, unit = m.group(1).rstrip(","), m.group(2), m.group(3)
        digits = whole.replace(",", "")
        if not digits:
            continue
        if "," not in whole and not frac and not unit and _YEAR.match(digits):
            continue  # a year such as 2026
        value = float(f"{digits}.{frac}" if frac else digits)
        multiplier = _MULTIPLIERS.get(unit, 1.0) if unit else 1.0
        if not frac and not unit and value <= IGNORE_SMALL_INTEGERS:
            continue
        step = 10 ** -len(frac) if frac else 1.0
        found.append((value * multiplier, step * multiplier / 2))
    return found


def collect_numbers(obj) -> set[float]:
    """Every number in tool outputs, plus absolute values (so "₹1,100 less" matches a difference of -1100)."""
    out: set[float] = set()
    if isinstance(obj, bool) or obj is None:
        return out
    if isinstance(obj, (int, float)):
        out.update({float(obj), abs(float(obj))})
    elif isinstance(obj, dict):
        for v in obj.values():
            out |= collect_numbers(v)
    elif isinstance(obj, (list, tuple)):
        for v in obj:
            out |= collect_numbers(v)
    return out


def ungrounded(text: str, known: set[float]) -> list[str]:
    bad = []
    for value, tol in extract_numbers(text):
        if not any(abs(value - k) <= tol + 1e-9 for k in known):
            bad.append(f"{value:g}")
    return bad


# ---------------------------------------------------------------- guardrail

_BANNED = re.compile(
    # "share" alone is allowed: "food was a 36% share of spending" is normal budgeting language.
    r"\b(stocks?|(stock|share)\s+market|equit(y|ies)|mutual\s+funds?|crypto\w*|bitcoin|invest\w*|loans?|"
    r"insurance|trading)\b",
    re.IGNORECASE,
)
_SIP = re.compile(r"\bSIPs?\b")  # case-sensitive: "sip" as in tea is fine


def banned_terms(text: str) -> list[str]:
    return sorted({m.group(0).lower() for m in _BANNED.finditer(text)} | {m.group(0) for m in _SIP.finditer(text)})


# ---------------------------------------------------------------- parse + validate

def parse_json(text: str) -> dict:
    """The model's answer as a JSON object. Strips ``` fences and any text around the outermost {...}."""
    t = (text or "").strip()
    t = re.sub(r"^```(?:json)?\s*|\s*```$", "", t, flags=re.IGNORECASE).strip()
    start, end = t.find("{"), t.rfind("}")
    if start == -1 or end <= start:
        raise CoachError("the answer was not a JSON object")
    try:
        obj = json.loads(t[start:end + 1])
    except json.JSONDecodeError as exc:
        raise CoachError(f"the answer was not valid JSON ({exc.msg})") from None
    if not isinstance(obj, dict):
        raise CoachError("the answer was not a JSON object")
    return obj


def _text(obj: dict, key: str, max_len: int, errors: list[str], where: str) -> str:
    value = obj.get(key)
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{where}.{key} must be a non-empty string")
        return ""
    if len(value) > max_len:
        errors.append(f"{where}.{key} must be {max_len} characters or fewer")
    return value.strip()


def _positive(value, where: str, errors: list[str]) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
        errors.append(f"{where} must be a positive number")
        return None
    return float(value)


def _validate_action(action, where: str, errors: list[str]) -> dict:
    if not isinstance(action, dict):
        errors.append(f"{where} must be an object")
        return {}
    kind = action.get("type")
    if kind not in ACTION_TYPES:
        errors.append(f"{where}.type must be one of: {', '.join(ACTION_TYPES)}")
        return {}
    if kind == "set_category_budget":
        if action.get("category") not in CATEGORIES:
            errors.append(f"{where}.category must be one of: {', '.join(CATEGORIES)}")
        amount = _positive(action.get("amount"), f"{where}.amount", errors)
        return {"type": kind, "category": action.get("category"), "amount": amount}
    if kind == "create_goal":
        name = _text(action, "name", 80, errors, where)
        amount = _positive(action.get("target_amount"), f"{where}.target_amount", errors)
        clean = {"type": kind, "name": name, "target_amount": amount}
        if action.get("target_date"):
            try:
                clean["target_date"] = date.fromisoformat(str(action["target_date"])).isoformat()
            except ValueError:
                errors.append(f"{where}.target_date must be YYYY-MM-DD")
        return clean
    return {"type": kind, "note": _text(action, "note", 80, errors, where)}


def validate_report(obj: dict, known_numbers: set[float]) -> tuple[dict, list[str]]:
    """Returns (clean report, errors). An empty error list means the report can be shown."""
    errors: list[str] = []
    win = _text(obj, "win", 240, errors, "report")

    suggestions_in = obj.get("suggestions")
    if not isinstance(suggestions_in, list) or not suggestions_in:
        errors.append("report.suggestions must be a list with 1 to 3 items")
        suggestions_in = []
    elif len(suggestions_in) > MAX_SUGGESTIONS:
        errors.append(f"report.suggestions has {len(suggestions_in)} items; the maximum is {MAX_SUGGESTIONS}")

    suggestions = []
    for i, s in enumerate(suggestions_in[:MAX_SUGGESTIONS + 1]):
        where = f"suggestions[{i}]"
        if not isinstance(s, dict):
            errors.append(f"{where} must be an object")
            continue
        clean = {
            "title": _text(s, "title", 80, errors, where),
            "why": _text(s, "why", 300, errors, where),
            "action": _validate_action(s.get("action"), f"{where}.action", errors),
        }
        if s.get("est_monthly_saving") is not None:
            saving = s["est_monthly_saving"]
            if isinstance(saving, bool) or not isinstance(saving, (int, float)) or saving < 0:
                errors.append(f"{where}.est_monthly_saving must be a number of 0 or more")
            else:
                clean["est_monthly_saving"] = float(saving)
        suggestions.append(clean)

    report = {"win": win, "suggestions": suggestions}
    if obj.get("next_month_budget") is not None:
        report["next_month_budget"] = _positive(obj["next_month_budget"], "report.next_month_budget", errors)

    # Number grounding: the win and every reason may only quote numbers the tools produced.
    for where, text in [("win", win)] + [(f"suggestions[{i}].why", s["why"]) for i, s in enumerate(suggestions)]:
        bad = ungrounded(text, known_numbers)
        if bad:
            errors.append(f"{where} uses numbers not found in the facts or tool results: {', '.join(bad)}. "
                          "Copy numbers exactly from the tool results.")

    # Guardrail: budgeting only.
    texts = [win] + [t for s in suggestions for t in (s["title"], s["why"])]
    terms = banned_terms(" ".join(texts))
    if terms:
        errors.append(f"remove investment or credit advice (found: {', '.join(terms)}); budgeting and habits only")
    return report, errors


# ---------------------------------------------------------------- the pipeline

def _base(status: str, month: str) -> dict:
    return {
        "status": status,
        "month": month,
        "month_name": month_name(month),
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "disclaimer": DISCLAIMER,
    }


def _fallback(month: str, facts: dict, currency: str) -> dict:
    """A safe, fully computed report used when the model's answer can't be trusted."""
    win = (f"You tracked {facts['count']} expenses in {month_name(month)}, "
           f"{fmt_money(facts['total'], currency)} in total.")
    return {**_base("fallback", month), "win": win, "suggestions": []}


def _system(user: User, month: str, today: date) -> str:
    replacements = {
        "__MONTH_NAME__": month_name(month),
        "__MONTH__": month,
        "__TODAY__": today.isoformat(),
        "__CURRENCY__": user.currency,
        "__MONEY__": fmt_money(1250, user.currency),
        "__CATEGORIES__": ", ".join(CATEGORIES),
    }
    text = SYSTEM_PROMPT
    for k, v in replacements.items():
        text = text.replace(k, v)
    return text


def generate_report(user: User, today: date | None = None, month: str | None = None, client=None, post=None) -> dict:
    """Review `month` (default: last month) for `user`. Pass `client` or `post` to fake the model in tests.
    Raises llm.AgentError / AgentBusy when the model isn't configured or is rate-limited."""
    today = today or date.today()
    month = month or insights.previous_month(today)
    insights.parse_month(month)

    first = services.first_expense_date(user.id)
    history = (today - first).days + 1 if first else 0
    if history < MIN_HISTORY_DAYS:
        return {**_base("not_enough_data", month), "message": NOT_ENOUGH_DATA, "history_days": history}

    tools = CoachTools(user, month, today)
    facts = tools.call("month_summary", {"month": month})
    if facts["count"] == 0:
        return {**_base("not_enough_data", month), "history_days": history,
                "message": f"No expenses were logged in {month_name(month)}, so there is nothing to review yet."}
    comparison = tools.call("compare_months", {"month": month, "n": 4})

    messages: list[dict] = [{
        "role": "user",
        "content": (
            f"Review my spending for {month_name(month)} and reply with the JSON plan.\n\n"
            f"Facts (month_summary):\n{json.dumps(facts)}\n\n"
            f"Compared with the 3 months before (compare_months):\n{json.dumps(comparison)}"
        ),
    }]
    system = _system(user, month, today)

    for attempt in range(2):  # the first answer, then at most one repair
        try:
            answer = run_tool_loop(messages, system, COACH_TOOLS, tools.executor, client=client, post=post,
                                   max_tokens=1500)
        except TooManySteps:
            break
        try:
            report, errors = validate_report(parse_json(answer), collect_numbers(tools.outputs))
        except CoachError as exc:
            report, errors = {}, [str(exc)]
        if not errors:
            return {**_base("ok", month), **report}
        if attempt == 0:
            messages += [
                {"role": "assistant", "content": answer or "(empty)"},
                {"role": "user", "content": "Your plan has these problems:\n- " + "\n- ".join(errors)
                 + "\nFix them and reply with the corrected JSON only."},
            ]
    return _fallback(month, facts, user.currency)


# ---------------------------------------------------------------- CLI: try it locally

def register_cli(app) -> None:
    import click
    from flask.cli import AppGroup

    coach_cli = AppGroup("coach", help="Monthly money coach.")

    @coach_cli.command("preview")
    @click.argument("user_id")
    @click.option("--month", default=None, help="YYYY-MM to review (default: last month)")
    def preview(user_id: str, month: str | None):
        """Print the coach's report for USER_ID without saving anything."""
        from .extensions import db
        from .llm import AgentBusy, AgentError

        user = db.session.get(User, user_id)
        if user is None:
            raise click.ClickException(f"no user with id {user_id!r}")
        try:
            report = generate_report(user, month=month)
        except AgentError as exc:
            raise click.ClickException(f"the AI model isn't configured: {exc}") from None
        except AgentBusy as exc:
            raise click.ClickException(f"the AI model is busy, try again in a minute ({exc})") from None
        click.echo(json.dumps(report, indent=2, ensure_ascii=False))

    @coach_cli.command("seed-demo")
    def seed_demo():
        """Dev only: create user 'coach-demo' with 4 months of sample spending to try the coach on."""
        from flask import current_app

        from .extensions import db
        from .models import Expense

        if current_app.config["AUTH_MODE"] != "dev":
            raise click.ClickException("seed-demo only runs with AUTH_MODE=dev")
        uid = "coach-demo"
        user = services.get_or_create_user(uid, "coach-demo@example.com")
        db.session.query(Expense).filter_by(user_id=uid).delete()
        user.monthly_budget = 9000
        db.session.commit()

        review = insights.previous_month(date.today())
        for back in (3, 2, 1):  # three ordinary months
            y, m = insights.parse_month(insights.shift_month(review, -back))
            for day, amount, cat, note in [(5, 1400, "food", "swiggy"), (20, 1600, "food", "dinner out"),
                                           (15, 1000, "transport", "metro card"), (3, 649, "bills", "Netflix"),
                                           (12, 2200, "groceries", "bigbasket")]:
                services.add_expense(uid, {"amount": amount, "category": cat, "note": note,
                                           "spent_on": date(y, m, day).isoformat()})
        y, m = insights.parse_month(review)  # the review month: more food delivery, a shopping spike
        rows = [(5, 1500, "food", "swiggy"), (7, 1500, "food", "zomato"), (20, 1500, "food", "swiggy"),
                (27, 1200, "food", "dinner out"), (15, 780, "transport", "metro card"), (3, 649, "bills", "Netflix"),
                (12, 2100, "groceries", "bigbasket"), (19, 2400, "shopping", "shoes")]
        rows += [(d, 30, "food", "chai") for d in (8, 9, 10, 11, 14, 16, 17, 18)]
        for day, amount, cat, note in rows:
            services.add_expense(uid, {"amount": amount, "category": cat, "note": note,
                                       "spent_on": date(y, m, day).isoformat()})
        click.echo(f"Seeded '{uid}' with 4 months ending {review}. Now run: flask coach preview {uid}")

    app.cli.add_command(coach_cli)
