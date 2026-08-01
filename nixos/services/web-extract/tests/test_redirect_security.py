"""Tests for redirect handling: relative redirects, SSRF via redirect, and URL resolution."""

import httpx
import respx

from hermes_local_web_extract.security import resolve_redirect

# ── resolve_redirect unit tests ──────────────────────────────────────────────


def test_resolve_redirect_absolute():
    result = resolve_redirect("https://good.com/page", "https://example.com/")
    assert result == "https://good.com/page"


def test_resolve_redirect_absolute_path():
    result = resolve_redirect("/new-path", "https://example.com/old")
    assert result == "https://example.com/new-path"


def test_resolve_redirect_relative_path():
    result = resolve_redirect("../sibling", "https://example.com/a/b")
    assert result == "https://example.com/sibling"


def test_resolve_redirect_protocol_relative():
    result = resolve_redirect("//cdn.example.com/asset", "https://example.com/")
    assert result == "https://cdn.example.com/asset"


# ── SSRF-via-redirect API tests ───────────────────────────────────────────────


@respx.mock
def test_redirect_to_private_ip_blocked(client):
    """A redirect whose resolved target is a private IP must be blocked."""
    respx.get("https://example.com/redirect").mock(
        return_value=httpx.Response(
            302,
            headers={"location": "http://192.168.1.1/secret"},
        )
    )
    resp = client.post("/extract", json={"url": "https://example.com/redirect"})
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "BLOCKED_PRIVATE_ADDRESS"


@respx.mock
def test_redirect_to_loopback_blocked(client):
    """A redirect to localhost must be blocked."""
    respx.get("https://example.com/loop").mock(
        return_value=httpx.Response(
            301,
            headers={"location": "http://127.0.0.1/admin"},
        )
    )
    resp = client.post("/extract", json={"url": "https://example.com/loop"})
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "BLOCKED_PRIVATE_ADDRESS"


@respx.mock
def test_redirect_to_metadata_endpoint_blocked(client):
    """A redirect to the cloud metadata endpoint must be blocked."""
    respx.get("https://example.com/meta").mock(
        return_value=httpx.Response(
            302,
            headers={"location": "http://169.254.169.254/latest/meta-data/"},
        )
    )
    resp = client.post("/extract", json={"url": "https://example.com/meta"})
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "BLOCKED_PRIVATE_ADDRESS"


@respx.mock
def test_relative_redirect_to_public_url_allowed(client):
    """A relative redirect to a public path on the same host must be followed."""
    respx.get("https://example.com/old").mock(
        return_value=httpx.Response(
            301,
            headers={"location": "/new"},
        )
    )
    respx.get("https://example.com/new").mock(
        return_value=httpx.Response(
            200,
            content=(
                b"<html><body><p>Redirected content here, enough to pass quality check.</p>"
                b"</body></html>"
            ),
            headers={"content-type": "text/html"},
        )
    )
    resp = client.post("/extract", json={"url": "https://example.com/old"})
    assert resp.status_code == 200
    assert resp.json()["success"] is True


@respx.mock
def test_too_many_redirects_blocked(client):
    """Exceeding the redirect limit must return FETCH_ERROR."""
    # Chain of redirects that loops back to itself
    for i in range(7):
        respx.get(f"https://example.com/r{i}").mock(
            return_value=httpx.Response(
                302,
                headers={"location": f"https://example.com/r{i + 1}"},
            )
        )
    resp = client.post("/extract", json={"url": "https://example.com/r0"})
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "FETCH_ERROR"
