"""Business logic. Every function takes the signed-in user's id; nothing here trusts a user id from input."""

from calendar import monthrange
from datetime import date
from decimal import Decimal, InvalidOperation

from sqlalchemy import func, select

from .extensions import db
from .models import CATEGORIES, Expense, User

MAX_AMOUNT = Decimal("10000000")


class ValidationError(ValueError):
    pass


class NotFound(LookupError):
    pass


# ---------- parsing ----------

def parse_amount(value) -> Decimal:
    try:
        amount = Decimal(str(value)).quantize(Decimal("0.01"))
    except (InvalidOperation, ValueError, TypeError):
        raise ValidationError("amount must be a number") from None
    if amount <= 0:
        raise ValidationError("amount must be greater than 0")
    if amount > MAX_AMOUNT:
        raise ValidationError("amount is too large")
    return amount


def parse_category(value) -> str:
    cat = str(value or "").strip().lower()
    if cat not in CATEGORIES:
        raise ValidationError(f"category must be one of: {', '.join(CATEGORIES)}")
    return cat


def parse_date(value, field: str = "date") -> date:
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value))
    except ValueError:
        raise ValidationError(f"{field} must be YYYY-MM-DD") from None


def parse_note(value) -> str:
    note = str(value or "").strip()
    if len(note) > 200:
        raise ValidationError("note must be 200 characters or fewer")
    return note


def month_bounds(today: date) -> tuple[date, date]:
    last = monthrange(today.year, today.month)[1]
    return today.replace(day=1), today.replace(day=last)


# ---------- users ----------

def get_or_create_user(uid: str, email: str | None = None) -> User:
    user = db.session.get(User, uid)
    if user is None:
        user = User(id=uid, email=email)
        db.session.add(user)
        db.session.commit()
    elif email and user.email != email:
        user.email = email
        db.session.commit()
    return user


def update_user(user: User, data: dict) -> User:
    if "monthly_budget" in data:
        raw = data["monthly_budget"]
        if raw in (None, "", 0):
            user.monthly_budget = None
        else:
            user.monthly_budget = parse_amount(raw)
    if "currency" in data:
        cur = str(data["currency"] or "").strip().upper()
        if len(cur) != 3 or not cur.isalpha():
            raise ValidationError("currency must be a 3-letter code like INR")
        user.currency = cur
    db.session.commit()
    return user


def delete_user(user: User) -> None:
    # Explicit deletes so this also works on SQLite without foreign-key enforcement.
    from .models import ChatUsage

    db.session.query(Expense).filter_by(user_id=user.id).delete()
    db.session.query(ChatUsage).filter_by(user_id=user.id).delete()
    db.session.delete(user)
    db.session.commit()


# ---------- expenses ----------

def add_expense(user_id: str, data: dict, today: date | None = None) -> Expense:
    today = today or date.today()
    expense = Expense(
        user_id=user_id,
        amount=parse_amount(data.get("amount")),
        category=parse_category(data.get("category")),
        note=parse_note(data.get("note")),
        spent_on=parse_date(data["spent_on"], "spent_on") if data.get("spent_on") else today,
    )
    db.session.add(expense)
    db.session.commit()
    return expense


def get_expense(user_id: str, expense_id: int) -> Expense:
    expense = db.session.scalar(select(Expense).where(Expense.id == expense_id, Expense.user_id == user_id))
    if expense is None:
        raise NotFound("expense not found")
    return expense


def update_expense(user_id: str, expense_id: int, data: dict) -> Expense:
    expense = get_expense(user_id, expense_id)
    if "amount" in data:
        expense.amount = parse_amount(data["amount"])
    if "category" in data:
        expense.category = parse_category(data["category"])
    if "note" in data:
        expense.note = parse_note(data["note"])
    if "spent_on" in data:
        expense.spent_on = parse_date(data["spent_on"], "spent_on")
    db.session.commit()
    return expense


def delete_expense(user_id: str, expense_id: int) -> None:
    expense = get_expense(user_id, expense_id)
    db.session.delete(expense)
    db.session.commit()


def list_expenses(
    user_id: str,
    start: date | None = None,
    end: date | None = None,
    category: str | None = None,
    limit: int = 500,
) -> list[Expense]:
    q = select(Expense).where(Expense.user_id == user_id)
    if start:
        q = q.where(Expense.spent_on >= start)
    if end:
        q = q.where(Expense.spent_on <= end)
    if category:
        q = q.where(Expense.category == parse_category(category))
    limit = max(1, min(int(limit), 1000))
    q = q.order_by(Expense.spent_on.desc(), Expense.id.desc()).limit(limit)
    return list(db.session.scalars(q))


def summary(user_id: str, start: date, end: date) -> dict:
    rows = db.session.execute(
        select(Expense.category, func.sum(Expense.amount), func.count(Expense.id))
        .where(Expense.user_id == user_id, Expense.spent_on >= start, Expense.spent_on <= end)
        .group_by(Expense.category)
    ).all()
    by_category = sorted(
        ({"category": c, "total": float(t or 0), "count": n} for c, t, n in rows),
        key=lambda r: r["total"],
        reverse=True,
    )
    total = round(sum(r["total"] for r in by_category), 2)
    return {"start": start.isoformat(), "end": end.isoformat(), "total": total, "by_category": by_category}


def budget_status(user: User, today: date | None = None) -> dict:
    today = today or date.today()
    start, end = month_bounds(today)
    spent = summary(user.id, start, end)["total"]
    budget = float(user.monthly_budget) if user.monthly_budget is not None else None
    days_left = (end - today).days + 1
    result = {
        "month": today.strftime("%Y-%m"),
        "spent": spent,
        "budget": budget,
        "currency": user.currency,
        "days_left": days_left,
    }
    if budget is not None:
        remaining = round(budget - spent, 2)
        result["remaining"] = remaining
        result["safe_per_day"] = round(max(remaining, 0) / days_left, 2)
        result["used_pct"] = round(spent / budget * 100, 1) if budget else None
    return result
