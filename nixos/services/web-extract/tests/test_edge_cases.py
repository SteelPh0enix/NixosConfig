"""Tests for edge cases: plain text, non-200 responses, timeout message, DNS zero-result."""

import httpx
import pytest
import respx

from hermes_local_web_extract.errors import InvalidURLError
from hermes_local_web_extract.security import _resolve_and_check

# ── DNS zero-result ───────────────────────────────────────────────────────────


def test_zero_dns_results_raises(monkeypatch):
    """If getaddrinfo returns an empty list, InvalidURLError must be raised."""
    import socket

    monkeypatch.setattr(socket, "getaddrinfo", lambda *a, **kw: [])
    with pytest.raises(InvalidURLError, match="resolved to no addresses"):
        _resolve_and_check("empty.example.com", allow_private=False)


# ── Timeout error does not leak URL ──────────────────────────────────────────


@respx.mock
def test_fetch_timeout_message_has_no_url(client):
    """The FETCH_TIMEOUT error message must not contain the request URL."""
    respx.get("https://example.com/slow").mock(side_effect=httpx.TimeoutException("timeout"))
    resp = client.post("/extract", json={"url": "https://example.com/slow"})
    assert resp.status_code == 400
    data = resp.json()
    assert data["error"]["code"] == "FETCH_TIMEOUT"
    # The error message must not contain any URL fragment that could leak tokens
    assert "example.com" not in data["error"]["message"]
    assert "slow" not in data["error"]["message"]


# ── Plain text content type ───────────────────────────────────────────────────


@respx.mock
def test_plain_text_extraction(client):
    """text/plain content must be returned as text and markdown."""
    plain = b"Hello, this is plain text content.\nSecond line of content here."
    respx.get("https://example.com/file.txt").mock(
        return_value=httpx.Response(
            200,
            content=plain,
            headers={"content-type": "text/plain; charset=utf-8"},
        )
    )
    resp = client.post(
        "/extract",
        json={"url": "https://example.com/file.txt", "formats": ["text", "markdown", "metadata"]},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    assert "Hello" in (data["text"] or "")
    assert data["metadata"]["extractor"] == "plain-text"


# ── Non-200 status codes ──────────────────────────────────────────────────────


@respx.mock
def test_404_response_still_returns_content(client):
    """A 404 page with HTML body should be extracted and return success with status 404."""
    html = (
        b"<html><body><h1>Not Found</h1>"
        b"<p>The page you requested does not exist here.</p></body></html>"
    )
    respx.get("https://example.com/missing").mock(
        return_value=httpx.Response(
            404,
            content=html,
            headers={"content-type": "text/html"},
        )
    )
    resp = client.post(
        "/extract",
        json={"url": "https://example.com/missing", "formats": ["markdown", "metadata"]},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    assert data["metadata"]["status_code"] == 404


@respx.mock
def test_503_response_still_returns_content(client):
    """A 503 page with HTML body should be extracted; status code surfaced in metadata."""
    html = (
        b"<html><body>"
        b"<p>Service temporarily unavailable. Please try again later.</p></body></html>"
    )
    respx.get("https://example.com/down").mock(
        return_value=httpx.Response(
            503,
            content=html,
            headers={"content-type": "text/html"},
        )
    )
    resp = client.post(
        "/extract",
        json={"url": "https://example.com/down", "formats": ["markdown", "metadata"]},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    assert data["metadata"]["status_code"] == 503


# ── Firecrawl warnings not discarded ─────────────────────────────────────────


@respx.mock
def test_firecrawl_unsupported_formats_logged_not_fail(client):
    """Unsupported Firecrawl formats must be silently ignored, not cause a 400."""
    html = b"<html><body><p>Some extractable page content for testing here.</p></body></html>"
    respx.get("https://example.com/compat").mock(
        return_value=httpx.Response(200, content=html, headers={"content-type": "text/html"})
    )
    resp = client.post(
        "/v1/scrape",
        json={
            "url": "https://example.com/compat",
            "formats": ["markdown", "screenshot", "actions"],  # screenshot/actions unsupported
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    assert data["data"]["markdown"] is not None
