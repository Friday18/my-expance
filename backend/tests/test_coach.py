"""The coach pipeline against a scripted fake model: no API calls."""

import json
from datetime import date
from types import SimpleNamespace

import pytest

from app import services
from app.coach import CoachTools, generate_report, validate_report
from app.extensions import db
from app.models import CategoryBudget, Expense, Goal
from app.services import get_or_create_user

TODAY = date(2026, 10, 5)


def _text(t):
    return SimpleNamespace(type="text", text=t)


def _tool(id_, name, input_):
    return SimpleNamespace(type="tool_use", id=id_, name=name, input=input_)


class FakeClient:
    """Plays back scripted model turns and records what the server sent."""

    def __init__(self, turns):
        self.turns = list(turns)
        self.calls = []
        self.messages = self

    def create(self, **kwargs):
        self.calls.append(kwargs)
        content, stop = self.turns.pop(0)
        return SimpleNamespace(content=content, stop_reason=stop)


class NoModel:
    messages = property(lambda self: self)

    def create(self, **kwargs):
        raise AssertionError("the model must not be called")


def add(uid, amount, category, note, day):
    services.add_expense(uid, {"amount": amount, "category": category, "note": note, "spent_on": day})


def seed(uid="alice"):
    """Same months as test_insights.sample(): food rose 55% in September, transport fell 22%."""
    get_or_create_user(uid)
    for m in (6, 7, 8):
        add(uid, 1400, "food", f"dinner {m}-5", f"2026-{m:02d}-05")
        add(uid, 1600, "food", f"dinner {m}-20", f"2026-{m:02d}-20")
        add(uid, 1000, "transport", "metro card", f"2026-{m:02d}-15")
        add(uid, 649, "bills", "Netflix", f"2026-{m:02d}-03")
    for d in ("05", "07", "20"):
        add(uid, 1500, "food", f"dinner {d}", f"2026-09-{d}")
    for d in ("08", "09", "10", "11", "14"):
        add(uid, 30, "food", "chai", f"2026-09-{d}")
    add(uid, 780, "transport", "metro card", "2026-09-15")
    add(uid, 649, "bills", "Netflix", "2026-09-03")
    return services.get_or_create_user(uid)


def plan(win="Transport fell 22% to ₹780, ₹220 less than usual.",
         why="Food was ₹4,650 in September, 55% above your ₹3,000 average.", **extra):
    body = {
        "win": win,
        "suggestions": [{
            "title": "Cap food at ₹4,000",
            "why": why,
            "action": {"type": "set_category_budget", "category": "food", "amount": 4000},
            "est_monthly_saving": 650,
        }],
        "next_month_budget": 6000,
    }
    body.update(extra)
    return json.dumps(body)


def test_too_little_data_skips_the_model(app):
    user = get_or_create_user("alice")
    add("alice", 500, "food", "lunch", "2026-09-28")  # 8 days of history
    report = generate_report(user, today=TODAY, client=NoModel())
    assert report["status"] == "not_enough_data" and report["history_days"] == 8
    assert "3 weeks" in report["message"] and report["disclaimer"]


def test_valid_report_passes(app):
    user = seed()
    client = FakeClient([
        ([_tool("t1", "category_trend", {"category": "food"})], "tool_use"),
        ([_text("```json\n" + plan() + "\n```")], "end_turn"),
    ])
    report = generate_report(user, today=TODAY, client=client)

    assert report["status"] == "ok" and report["month"] == "2026-09" and report["month_name"] == "September 2026"
    assert report["win"].startswith("Transport fell 22%")
    assert report["suggestions"][0]["action"] == {"type": "set_category_budget", "category": "food", "amount": 4000.0}
    assert report["next_month_budget"] == 6000.0
    assert "not financial advice" in report["disclaimer"]  # added by the server, not the model
    # The facts were given up front; the system prompt names the review month.
    first = client.calls[0]
    assert "September 2026" in first["system"] and '"total": 6079.0' in first["messages"][0]["content"]
    # The tool result went back to the model.
    assert '"category": "food"' in client.calls[1]["messages"][-1]["content"][0]["content"]


def test_invented_number_is_repaired_once(app):
    user = seed()
    client = FakeClient([
        ([_text(plan(why="Food was ₹9,999 in September."))], "end_turn"),
        ([_text(plan())], "end_turn"),
    ])
    report = generate_report(user, today=TODAY, client=client)
    assert report["status"] == "ok"
    repair = client.calls[1]["messages"][-1]["content"]
    assert "9999" in repair and "not found in the facts" in repair and "JSON only" in repair


def test_invented_number_twice_gives_fallback(app):
    user = seed()
    bad = plan(win="You saved ₹12,345 this month!")
    client = FakeClient([([_text(bad)], "end_turn"), ([_text(bad)], "end_turn")])
    report = generate_report(user, today=TODAY, client=client)
    assert report["status"] == "fallback" and report["suggestions"] == []
    assert report["win"] == "You tracked 10 expenses in September 2026, ₹6,079 in total."
    assert len(client.calls) == 2


def test_not_json_twice_gives_fallback(app):
    user = seed()
    client = FakeClient([([_text("Here are my tips!")], "end_turn"), ([_text("Sorry!")], "end_turn")])
    assert generate_report(user, today=TODAY, client=client)["status"] == "fallback"


def test_investment_advice_is_rejected(app):
    known = {4650.0, 55.0, 3000.0}
    obj = json.loads(plan(win="Great month for food!", why="Food was ₹4,650; start a SIP or invest the rest."))
    _, errors = validate_report(obj, known)
    assert any("investment" in e and "SIP" in e for e in errors)


def test_too_many_suggestions_and_unknown_action_are_rejected(app):
    one = {"title": "Spend less", "why": "Food was ₹4,650.", "action": {"type": "buy_gold", "grams": 2}}
    obj = {"win": "Good month.", "suggestions": [one] * 4}
    _, errors = validate_report(obj, {4650.0})
    assert any("maximum is 3" in e for e in errors)
    assert any("action.type must be one of" in e for e in errors)

    bad_budget = {"type": "set_category_budget", "category": "gold", "amount": -5}
    _, errors = validate_report({"win": "Good month.", "suggestions": [{**one, "action": bad_budget}]}, {4650.0})
    assert any("category must be one of" in e for e in errors) and any("positive number" in e for e in errors)


def test_coach_tools_never_change_the_database(app):
    user = seed()
    services.create_goal(user.id, {"name": "Goa trip", "target_amount": 30000, "saved_amount": 5000,
                                   "target_date": "2027-01-31"})
    services.set_category_budget(user.id, "food", 4000)
    user.monthly_budget = 8000
    db.session.commit()

    def snapshot():
        return (
            [e.to_dict() for e in Expense.query.order_by(Expense.id)],
            [g.to_dict() for g in Goal.query.order_by(Goal.id)],
            [b.to_dict() for b in CategoryBudget.query.order_by(CategoryBudget.category)],
            float(user.monthly_budget),
        )

    before = snapshot()
    tools = CoachTools(user, "2026-09", TODAY)
    for name, args in [("month_summary", {}), ("compare_months", {"n": 3}), ("category_trend", {"category": "food"}),
                       ("recurring_payments", {}), ("budget_status", {}), ("goals_status", {})]:
        content, is_error = tools.executor(name, args)
        assert not is_error, content
    assert snapshot() == before and not db.session.dirty and not db.session.new

    goals = tools.call("goals_status", {})["goals"]
    assert goals[0]["pct_done"] == round(5000 / 30000 * 100, 1) and goals[0]["months_left"] == 3
    status = tools.call("budget_status", {})
    assert status["overall"]["budget"] == 8000.0 and status["categories"][0]["category"] == "food"
    # Bad input is reported to the model, not raised.
    content, is_error = tools.executor("month_summary", {"month": "2019-01"})
    assert is_error and content.startswith("Error: month must be between")


def test_coach_tools_only_see_the_signed_in_user(app):
    alice = seed("alice")
    get_or_create_user("bob")
    add("bob", 99999, "shopping", "tv", "2026-09-10")
    summary = CoachTools(alice, "2026-09", TODAY).call("month_summary", {})
    assert summary["total"] == 6079.0 and "shopping" not in {c["category"] for c in summary["by_category"]}


def test_delete_account_removes_goals_and_budgets(app):
    user = seed()
    services.create_goal(user.id, {"name": "Laptop", "target_amount": 60000})
    services.set_category_budget(user.id, "food", 4000)
    services.delete_user(user)
    assert Goal.query.count() == 0 and CategoryBudget.query.count() == 0 and Expense.query.count() == 0


def test_set_category_budget_replaces_existing(app):
    get_or_create_user("alice")
    services.set_category_budget("alice", "food", 4000)
    services.set_category_budget("alice", "FOOD", 3500)
    assert [b.to_dict() for b in services.list_category_budgets("alice")] == [{"category": "food", "amount": 3500.0}]
    with pytest.raises(services.ValidationError):
        services.set_category_budget("alice", "gold", 100)
