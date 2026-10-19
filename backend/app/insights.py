"""Pure maths for the monthly coach: no database, no AI.

Every percentage, average and difference the coach might quote is computed here and rounded once, so the
model only ever copies numbers and never calculates them. All functions take plain `Txn` records.
"""

from calendar import monthrange
from collections import defaultdict
from dataclasses import dataclass
from datetime import date
from statistics import median

SMALL_SPEND = 200.0  # "small frequent spends" threshold, in the user's currency
RECURRING_TOLERANCE = 0.10  # amounts within ±10% of their median count as the same recurring payment


@dataclass(frozen=True)
class Txn:
    amount: float
    category: str
    note: str
    spent_on: date


# ---------------------------------------------------------------- helpers

def month_key(d: date) -> str:
    return f"{d.year:04d}-{d.month:02d}"


def parse_month(key: str) -> tuple[int, int]:
    try:
        year, month = (int(p) for p in str(key).split("-"))
    except ValueError:
        raise ValueError("month must be YYYY-MM") from None
    if not (1 <= month <= 12 and 2000 <= year <= 2100):
        raise ValueError("month must be YYYY-MM")
    return year, month


def shift_month(key: str, delta: int) -> str:
    year, month = parse_month(key)
    index = year * 12 + (month - 1) + delta
    return f"{index // 12:04d}-{index % 12 + 1:02d}"


def month_bounds(key: str) -> tuple[date, date]:
    year, month = parse_month(key)
    return date(year, month, 1), date(year, month, monthrange(year, month)[1])


def previous_month(today: date) -> str:
    return shift_month(month_key(today), -1)


def money(x: float) -> float:
    return round(float(x), 2)


def pct(part: float, whole: float) -> float | None:
    return round(part / whole * 100, 1) if whole else None


def change_pct(new: float, old: float) -> float | None:
    return round((new - old) / old * 100, 1) if old else None


def _in_month(txns: list[Txn], key: str) -> list[Txn]:
    start, end = month_bounds(key)
    return [t for t in txns if start <= t.spent_on <= end]


def _month_total(txns: list[Txn], key: str) -> float:
    return money(sum(t.amount for t in _in_month(txns, key)))


def _by_category(txns: list[Txn]) -> dict[str, float]:
    totals: dict[str, float] = defaultdict(float)
    for t in txns:
        totals[t.category] += t.amount
    return {c: money(v) for c, v in totals.items()}


def days_of_history(txns: list[Txn], today: date) -> int:
    if not txns:
        return 0
    return (today - min(t.spent_on for t in txns)).days + 1


# ---------------------------------------------------------------- the coach's facts

def month_summary(txns: list[Txn], key: str, today: date) -> dict:
    """Total, categories with shares, daily average, weekend share, small spends and the biggest expense."""
    start, end = month_bounds(key)
    items = _in_month(txns, key)
    complete = today > end
    days_counted = (end - start).days + 1 if complete else max(0, (min(today, end) - start).days + 1)
    total = money(sum(t.amount for t in items))
    counts: dict[str, int] = defaultdict(int)
    for t in items:
        counts[t.category] += 1
    categories = sorted(
        ({"category": c, "total": v, "count": counts[c], "share_pct": pct(v, total)}
         for c, v in _by_category(items).items()),
        key=lambda r: r["total"],
        reverse=True,
    )
    weekend = money(sum(t.amount for t in items if t.spent_on.weekday() >= 5))
    small = [t for t in items if t.amount < SMALL_SPEND]
    biggest = max(items, key=lambda t: t.amount, default=None)
    return {
        "month": key,
        "complete": complete,
        "total": total,
        "count": len(items),
        "by_category": categories,
        "daily_average": money(total / days_counted) if days_counted else 0.0,
        "days_with_spending": len({t.spent_on for t in items}),
        "weekend_total": weekend,
        "weekend_share_pct": pct(weekend, total),
        "small_spends": {
            "under": SMALL_SPEND,
            "count": len(small),
            "total": money(sum(t.amount for t in small)),
            "share_pct": pct(sum(t.amount for t in small), total),
        },
        "biggest_expense": None if biggest is None else {
            "amount": money(biggest.amount), "category": biggest.category,
            "note": biggest.note, "spent_on": biggest.spent_on.isoformat(),
        },
    }


def compare_months(txns: list[Txn], end_key: str, n: int = 4) -> dict:
    """The month `end_key` against the average of the n-1 months before it, overall and per category."""
    n = max(2, min(int(n), 6))
    keys = [shift_month(end_key, -i) for i in range(n - 1, -1, -1)]  # oldest -> newest
    months = []
    for k in keys:
        items = _in_month(txns, k)
        months.append({"month": k, "total": money(sum(t.amount for t in items)), "by_category": _by_category(items)})
    latest, previous = months[-1], months[:-1]
    prev_avg_total = money(sum(m["total"] for m in previous) / len(previous))

    categories = sorted({c for m in months for c in m["by_category"]})
    per_category = []
    for c in categories:
        prev_avg = money(sum(m["by_category"].get(c, 0.0) for m in previous) / len(previous))
        now = latest["by_category"].get(c, 0.0)
        per_category.append({
            "category": c,
            "latest": now,
            "previous_average": prev_avg,
            "difference": money(now - prev_avg),
            "change_pct": change_pct(now, prev_avg),
        })
    per_category.sort(key=lambda r: abs(r["difference"]), reverse=True)
    return {
        "latest_month": end_key,
        "months": months,
        "latest_total": latest["total"],
        "previous_average_total": prev_avg_total,
        "difference": money(latest["total"] - prev_avg_total),
        "change_pct": change_pct(latest["total"], prev_avg_total),
        "by_category": per_category,
    }


def category_trend(txns: list[Txn], category: str, end_key: str, months: int = 6) -> dict:
    """One category over the last `months` months ending at `end_key`, and how the last compares to the rest."""
    keys = [shift_month(end_key, -i) for i in range(months - 1, -1, -1)]
    series = [{"month": k, "total": money(sum(t.amount for t in _in_month(txns, k) if t.category == category))}
              for k in keys]
    latest = series[-1]["total"]
    prev = [s["total"] for s in series[:-1]]
    prev_avg = money(sum(prev) / len(prev)) if prev else 0.0
    return {
        "category": category,
        "months": series,
        "latest": latest,
        "previous_average": prev_avg,
        "difference": money(latest - prev_avg),
        "change_pct": change_pct(latest, prev_avg),
        "times_previous_average": round(latest / prev_avg, 1) if prev_avg else None,
    }


def _norm(note: str) -> str:
    return " ".join(note.lower().split())


def recurring_payments(txns: list[Txn], end_key: str) -> dict:
    """Same note and category, similar amount (±10%), in at least 2 of the 3 months ending at `end_key`."""
    keys = [shift_month(end_key, -i) for i in range(2, -1, -1)]
    start, _ = month_bounds(keys[0])
    _, end = month_bounds(keys[-1])
    groups: dict[tuple[str, str], list[Txn]] = defaultdict(list)
    for t in txns:
        if start <= t.spent_on <= end and _norm(t.note):
            groups[(_norm(t.note), t.category)].append(t)

    found = []
    for (_note, category), items in groups.items():
        months_seen = sorted({month_key(t.spent_on) for t in items})
        if len(months_seen) < 2:
            continue
        typical = median(t.amount for t in items)
        if any(abs(t.amount - typical) > typical * RECURRING_TOLERANCE for t in items):
            continue
        last = max(items, key=lambda t: t.spent_on)
        found.append({
            "note": last.note,
            "category": category,
            "typical_amount": money(typical),
            "months_seen": len(months_seen),
            "last_paid_on": last.spent_on.isoformat(),
        })
    found.sort(key=lambda r: r["typical_amount"], reverse=True)
    return {
        "months_checked": keys,
        "payments": found,
        "count": len(found),
        "monthly_total": money(sum(r["typical_amount"] for r in found)),
    }


def budget_pace(budget: float, spent: float, today: date) -> dict:
    """Where spending stands against a monthly budget today, and where it lands at this pace."""
    days = monthrange(today.year, today.month)[1]
    day = today.day
    expected = budget * day / days
    projected = spent / day * days if day else spent
    return {
        "budget": money(budget),
        "spent": money(spent),
        "remaining": money(budget - spent),
        "used_pct": pct(spent, budget),
        "expected_by_today": money(expected),
        "projected_month_end": money(projected),
        "projected_over_by": money(max(0.0, projected - budget)),
        "on_pace": spent <= expected * 1.05,
        "days_left": days - day + 1,
    }


def goal_status(name: str, target: float, saved: float, target_date: date | None, today: date) -> dict:
    remaining = max(0.0, target - saved)
    months_left = None
    monthly_needed = None
    if target_date is not None:
        months_left = max(0, (target_date.year - today.year) * 12 + (target_date.month - today.month))
        if months_left and remaining:
            monthly_needed = money(remaining / months_left)
    return {
        "name": name,
        "target": money(target),
        "saved": money(saved),
        "remaining": money(remaining),
        "pct_done": pct(min(saved, target), target),
        "target_date": target_date.isoformat() if target_date else None,
        "months_left": months_left,
        "monthly_needed": monthly_needed,
    }
