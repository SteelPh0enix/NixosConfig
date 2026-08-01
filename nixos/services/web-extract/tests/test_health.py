"""Tests for health endpoints."""


def test_healthz_ok(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    assert data["status"] == "ok"


def test_readyz_ok(client):
    resp = client.get("/readyz")
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    assert data["status"] == "ok"


def test_v1_health_ok(client):
    resp = client.get("/v1/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    assert data["status"] == "ok"


def test_healthz_has_version(client):
    resp = client.get("/healthz")
    assert "version" in resp.json()
