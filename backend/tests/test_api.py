from datetime import date

from conftest import auth


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.get_json() == {"status": "ok"}


def test_requires_auth(client):
    assert client.get("/api/expenses").status_code == 401
    assert client.get("/api/expenses", headers={"Authorization": "Bearer "}).status_code == 401


def test_create_and_list_expenses(client):
    r = client.post(
        "/api/expenses",
        json={"amount": 450, "category": "Food", "note": "lunch", "spent_on": "2026-10-14"},
        headers=auth(),
    )
    assert r.status_code == 201
    body = r.get_json()
    assert body["amount"] == 450.0 and body["category"] == "food" and body["spent_on"] == "2026-10-14"

    client.post("/api/expenses", json={"amount": 220, "category": "transport"}, headers=auth())
    items = client.get("/api/expenses", headers=auth()).get_json()["expenses"]
    assert len(items) == 2
    assert items[0]["spent_on"] == date.today().isoformat()  # newest first

    food = client.get("/api/expenses?category=food", headers=auth()).get_json()["expenses"]
    assert [e["note"] for e in food] == ["lunch"]


def test_validation(client):
    bad = [
        {"amount": -5, "category": "food"},
        {"amount": "abc", "category": "food"},
        {"amount": 10, "category": "rockets"},
        {"amount": 10, "category": "food", "spent_on": "14/10/2026"},
        {"amount": 10, "category": "food", "note": "x" * 201},
    ]
    for payload in bad:
        r = client.post("/api/expenses", json=payload, headers=auth())
        assert r.status_code == 400, payload
        assert "error" in r.get_json()
    assert client.post("/api/expenses", data="nope", headers=auth()).status_code == 400


def test_update_and_delete(client):
    eid = client.post("/api/expenses", json={"amount": 100, "category": "food"}, headers=auth()).get_json()["id"]
    r = client.patch(f"/api/expenses/{eid}", json={"amount": 120.5, "note": "dinner"}, headers=auth())
    assert r.status_code == 200 and r.get_json()["amount"] == 120.5 and r.get_json()["note"] == "dinner"
    assert client.delete(f"/api/expenses/{eid}", headers=auth()).status_code == 204
    assert client.delete(f"/api/expenses/{eid}", headers=auth()).status_code == 404


def test_user_isolation(client):
    eid = client.post("/api/expenses", json={"amount": 99, "category": "food"}, headers=auth("alice")).get_json()["id"]
    assert client.get("/api/expenses", headers=auth("bob")).get_json()["expenses"] == []
    assert client.patch(f"/api/expenses/{eid}", json={"amount": 1}, headers=auth("bob")).status_code == 404
    assert client.delete(f"/api/expenses/{eid}", headers=auth("bob")).status_code == 404
    assert len(client.get("/api/expenses", headers=auth("alice")).get_json()["expenses"]) == 1


def test_budget_and_summary(client):
    r = client.patch("/api/me", json={"monthly_budget": 10000, "currency": "inr"}, headers=auth())
    assert r.get_json()["monthly_budget"] == 10000.0 and r.get_json()["currency"] == "INR"
    client.post("/api/expenses", json={"amount": 300, "category": "food"}, headers=auth())
    client.post("/api/expenses", json={"amount": 200, "category": "food"}, headers=auth())
    client.post("/api/expenses", json={"amount": 1000, "category": "bills"}, headers=auth())

    s = client.get("/api/summary", headers=auth()).get_json()
    assert s["total"] == 1500.0
    assert s["by_category"][0] == {"category": "bills", "total": 1000.0, "count": 1}
    assert s["budget"]["remaining"] == 8500.0
    assert s["budget"]["safe_per_day"] > 0


def test_delete_account(client):
    client.post("/api/expenses", json={"amount": 50, "category": "food"}, headers=auth())
    assert client.delete("/api/me", headers=auth()).status_code == 204
    # Signing in again starts a brand-new, empty account.
    assert client.get("/api/expenses", headers=auth()).get_json()["expenses"] == []
    assert client.get("/api/me", headers=auth()).get_json()["monthly_budget"] is None


def test_firebase_token_check(app, client, monkeypatch):
    import app.auth as auth_module

    app.config.update(AUTH_MODE="firebase", FIREBASE_PROJECT_ID="my-expance")

    def fake_verify(token, project_id):
        if token != "good-token":
            raise ValueError("bad token")
        return {"sub": "firebase-uid-1", "email": "a@example.com"}

    monkeypatch.setattr(auth_module, "verify_firebase_token", fake_verify)
    assert client.get("/api/me", headers={"Authorization": "Bearer forged"}).status_code == 401
    r = client.get("/api/me", headers={"Authorization": "Bearer good-token"})
    assert r.status_code == 200
    assert r.get_json()["id"] == "firebase-uid-1" and r.get_json()["email"] == "a@example.com"
