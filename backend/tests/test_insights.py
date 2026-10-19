"""Unit tests for the coach's pure maths and number grounding (no database, no model)."""

from datetime import date

from app.coach import banned_terms, collect_numbers, extract_numbers, fmt_money, ungrounded
from app.insights import (
    Txn,
    budget_pace,
    category_trend,
    compare_months,
    goal_status,
    month_summary,
    recurring_payments,
    shift_month,
)


def sample() -> list[Txn]:
    """Jun-Aug: food 3,000, transport 1,000, Netflix 649. Sep: food 4,500 + 5 chai of 30, transport 780, Netflix."""
    txns = []
    for m in (6, 7, 8):
        txns += [
            Txn(1400, "food", f"dinner {m}-5", date(2026, m, 5)),
            Txn(1600, "food", f"dinner {m}-20", date(2026, m, 20)),
            Txn(1000, "transport", "metro card", date(2026, m, 15)),
            Txn(649, "bills", "Netflix", date(2026, m, 3)),
        ]
    txns += [
        Txn(1500, "food", "dinner sat", date(2026, 9, 5)),  # Saturday
        Txn(1500, "food", "dinner mon", date(2026, 9, 7)),  # Monday
        Txn(1500, "food", "dinner sun", date(2026, 9, 20)),  # Sunday
        *[Txn(30, "food", "chai", date(2026, 9, d)) for d in (8, 9, 10, 11, 14)],  # weekdays
        Txn(780, "transport", "metro card", date(2026, 9, 15)),
        Txn(649, "bills", "Netflix", date(2026, 9, 3)),
    ]
    return txns


TODAY = date(2026, 10, 5)


def test_shift_month_crosses_years():
    assert shift_month("2026-01", -1) == "2025-12"
    assert shift_month("2026-11", 3) == "2027-02"


def test_month_summary():
    s = month_summary(sample(), "2026-09", TODAY)
    assert s["complete"] is True
    assert s["total"] == 6079.0 and s["count"] == 10
    assert s["by_category"][0] == {"category": "food", "total": 4650.0, "count": 8, "share_pct": 76.5}
    assert s["daily_average"] == round(6079 / 30, 2)
    assert s["weekend_total"] == 3000.0 and s["weekend_share_pct"] == round(3000 / 6079 * 100, 1)
    assert s["small_spends"]["count"] == 5 and s["small_spends"]["total"] == 150.0
    assert s["biggest_expense"]["amount"] == 1500.0


def test_month_summary_current_month_uses_days_so_far():
    txns = [Txn(500, "food", "", date(2026, 10, 2))]
    s = month_summary(txns, "2026-10", TODAY)
    assert s["complete"] is False and s["daily_average"] == 100.0  # 500 over 5 days


def test_compare_months():
    c = compare_months(sample(), "2026-09", 4)
    assert [m["month"] for m in c["months"]] == ["2026-06", "2026-07", "2026-08", "2026-09"]
    assert c["previous_average_total"] == 4649.0 and c["latest_total"] == 6079.0
    assert c["difference"] == 1430.0 and c["change_pct"] == 30.8
    by = {r["category"]: r for r in c["by_category"]}
    assert by["food"]["previous_average"] == 3000.0 and by["food"]["change_pct"] == 55.0
    assert by["transport"]["difference"] == -220.0 and by["transport"]["change_pct"] == -22.0
    assert by["bills"]["change_pct"] == 0.0


def test_category_trend():
    t = category_trend(sample(), "food", "2026-09")
    assert [m["total"] for m in t["months"]] == [0.0, 0.0, 3000.0, 3000.0, 3000.0, 4650.0]
    assert t["previous_average"] == 1800.0 and t["times_previous_average"] == 2.6
    assert t["change_pct"] == round((4650 - 1800) / 1800 * 100, 1)


def test_recurring_payments_finds_netflix_not_variable_spend():
    r = recurring_payments(sample(), "2026-09")
    assert [p["note"] for p in r["payments"]] == ["Netflix"]
    assert r["payments"][0]["typical_amount"] == 649.0 and r["payments"][0]["months_seen"] == 3
    # Metro card went from 1,000 to 780 (22% lower), so it isn't treated as the same fixed payment.


def test_budget_pace_and_goals():
    p = budget_pace(31000, 15000, date(2026, 10, 10))
    assert p["expected_by_today"] == 10000.0 and p["projected_month_end"] == 46500.0
    assert p["projected_over_by"] == 15500.0 and p["on_pace"] is False and p["days_left"] == 22
    g = goal_status("Goa trip", 30000, 12000, date(2027, 1, 31), TODAY)
    assert g["pct_done"] == 40.0 and g["months_left"] == 3 and g["monthly_needed"] == 6000.0


def test_extract_numbers():
    nums = [v for v, _ in extract_numbers("₹1,25,000 and ₹6,450.50, up 38% (2.1× usual), ₹1.2k, ₹3.4L in 2026")]
    assert nums == [125000.0, 6450.5, 38.0, 2.1, 1200.0, 340000.0]
    # Years and small counts are not checked.
    assert extract_numbers("3 months in 2026, 2 subscriptions") == []


def test_grounding_tolerance():
    known = collect_numbers({"a": 38.2, "b": -220.0, "c": [6450.0], "d": True})
    assert ungrounded("38% more, ₹220 less, ₹6,450 total", known) == []
    assert ungrounded("₹1.2k", {1180.0}) == []  # "1.2k" means anything from 1,150 to 1,250
    assert ungrounded("₹9,999 on food, 40% up", known) == ["9999", "40"]


def test_banned_terms():
    assert banned_terms("Start a SIP and invest in mutual funds") == ["SIP", "invest", "mutual funds"]
    assert banned_terms("Food was a 36% share; sip chai at home") == []


def test_fmt_money():
    assert fmt_money(125000) == "₹1,25,000" and fmt_money(649) == "₹649"
    assert fmt_money(125000, "USD") == "$125,000" and fmt_money(-220) == "-₹220"
