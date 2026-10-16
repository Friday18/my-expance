from datetime import date
from types import SimpleNamespace

from conftest import auth

import app.routes.api as api_module
from app.agent import run_agent
from app.models import Expense
from app.services import get_or_create_user


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


def test_agent_tool_loop(app):
    user = get_or_create_user("alice")
    client = FakeClient(
        [
            # Tries to log an expense for someone else: the extra user_id field is ignored.
            ([_tool("t1", "add_expense", {"amount": 450, "category": "food", "note": "lunch", "user_id": "bob"})],
             "tool_use"),
            ([_tool("t2", "add_expense", {"amount": -1, "category": "food"})], "tool_use"),
            ([_text("Logged ₹450 for lunch.")], "end_turn"),
        ]
    )
    out = run_agent([{"role": "user", "content": "spent 450 on lunch"}], user, client=client, today=date(2026, 10, 15))

    assert out["reply"] == "Logged ₹450 for lunch."
    assert [a["type"] for a in out["actions"]] == ["added"]
    rows = Expense.query.all()
    assert len(rows) == 1 and rows[0].user_id == "alice" and rows[0].spent_on == date(2026, 10, 15)

    # The invalid second call was reported back to the model as an error, not raised.
    last_sent = client.calls[2]["messages"][-1]["content"][0]
    assert last_sent["is_error"] is True and "greater than 0" in last_sent["content"]
    assert "2026-10-15" in client.calls[0]["system"]


def test_chat_daily_quota(client, monkeypatch):
    monkeypatch.setattr(api_module, "run_agent", lambda messages, user: {"reply": "ok", "actions": []})
    body = {"messages": [{"role": "user", "content": "hi"}]}
    for _ in range(3):  # CHAT_DAILY_LIMIT is 3 in tests
        assert client.post("/api/chat", json=body, headers=auth()).status_code == 200
    r = client.post("/api/chat", json=body, headers=auth())
    assert r.status_code == 429
    # Another user has their own quota.
    assert client.post("/api/chat", json=body, headers=auth("bob")).status_code == 200
    # Bad payloads are rejected before using quota.
    assert client.post("/api/chat", json={"messages": []}, headers=auth("bob")).status_code == 400


def test_agent_openai_compatible_loop(app):
    """The free providers (Groq, Gemini, Ollama) speak the OpenAI chat-completions format."""
    app.config.update(LLM_PROVIDER="groq", GROQ_API_KEY="test-key")
    user = get_or_create_user("alice")
    turns = [
        {"choices": [{"message": {"content": None, "tool_calls": [
            {"id": "c1", "type": "function",
             "function": {"name": "add_expense",
                          "arguments": '{"amount": 220, "category": "transport", "note": "uber"}'}},
            {"id": "c2", "type": "function", "function": {"name": "add_expense", "arguments": "not json"}},
        ]}}]},
        {"choices": [{"message": {"content": "Logged ₹220 for your Uber."}}]},
    ]
    sent = []

    def fake_post(url, payload, key):
        sent.append((url, payload, key))
        return turns.pop(0)

    out = run_agent([{"role": "user", "content": "uber 220"}], user, today=date(2026, 10, 15), post=fake_post)
    assert out["reply"] == "Logged ₹220 for your Uber."
    assert [a["type"] for a in out["actions"]] == ["added"]
    assert Expense.query.one().amount == 220
    url, payload, key = sent[1]
    assert url == "https://api.groq.com/openai/v1/chat/completions" and key == "test-key"
    assert payload["messages"][0]["role"] == "system"
    tool_msgs = [m for m in payload["messages"] if m["role"] == "tool"]
    assert [m["tool_call_id"] for m in tool_msgs] == ["c1", "c2"]
    assert tool_msgs[1]["content"].startswith("Error:")


def test_openai_post_retries_then_reports_busy(monkeypatch):
    import pytest

    import app.agent as agent_module

    statuses = [503, 503, 200]

    class Resp:
        def __init__(self, code):
            self.status_code, self.text = code, "overloaded"

        def json(self):
            return {"ok": True}

    calls = []
    monkeypatch.setattr(agent_module.requests, "post", lambda *a, **k: calls.append(1) or Resp(statuses.pop(0)))
    assert agent_module.openai_post("u", {}, "k", sleep=lambda s: None) == {"ok": True}
    assert len(calls) == 3

    statuses[:] = [503, 503, 503]
    with pytest.raises(agent_module.AgentBusy):
        agent_module.openai_post("u", {}, "k", sleep=lambda s: None)
