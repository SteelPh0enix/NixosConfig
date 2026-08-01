"""Tests for the native POST /extract endpoint."""

import httpx
import respx

_SAMPLE_HTML = b"""<!DOCTYPE html>
<html><head><title>Sample Page</title></head>
<body><main><h1>Hello World</h1>
<p>This is sample content for extraction testing. It has enough text to pass quality checks.</p>
<p>Second paragraph adds more context and ensures the extractor has substance to work with.</p>
</main></body></html>"""


def test_extract_missing_url(client):
    resp = client.post("/extract", json={})
    assert resp.status_code == 422


def test_extract_invalid_scheme(client):
    resp = client.post("/extract", json={"url": "file:///etc/passwd"})
    assert resp.status_code == 400
    data = resp.json()
    assert data["success"] is False
    assert data["error"]["code"] == "INVALID_URL"


def test_extract_localhost_blocked(client):
    resp = client.post("/extract", json={"url": "http://localhost/secret"})
    assert resp.status_code in (400, 422)
    data = resp.json()
    assert data["success"] is False


def test_extract_loopback_ip_blocked(client):
    resp = client.post("/extract", json={"url": "http://127.0.0.1/"})
    assert resp.status_code == 400
    data = resp.json()
    assert data["error"]["code"] == "BLOCKED_PRIVATE_ADDRESS"


def test_extract_private_ip_blocked(client):
    resp = client.post("/extract", json={"url": "http://192.168.1.1/"})
    assert resp.status_code == 400
    data = resp.json()
    assert data["error"]["code"] == "BLOCKED_PRIVATE_ADDRESS"


def test_extract_metadata_endpoint_blocked(client):
    resp = client.post("/extract", json={"url": "http://169.254.169.254/"})
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "BLOCKED_PRIVATE_ADDRESS"


@respx.mock
def test_extract_html_success(client):
    respx.get("https://example.com/article").mock(
        return_value=httpx.Response(
            200,
            content=_SAMPLE_HTML,
            headers={"content-type": "text/html; charset=utf-8"},
        )
    )
    resp = client.post(
        "/extract",
        json={"url": "https://example.com/article", "formats": ["markdown", "text", "metadata"]},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    assert data["url"] == "https://example.com/article"
    assert isinstance(data["markdown"], str)
    assert isinstance(data["text"], str)
    assert data["metadata"] is not None


@respx.mock
def test_extract_returns_title(client):
    respx.get("https://example.com/titled").mock(
        return_value=httpx.Response(
            200,
            content=_SAMPLE_HTML,
            headers={"content-type": "text/html"},
        )
    )
    resp = client.post(
        "/extract",
        json={"url": "https://example.com/titled", "formats": ["markdown", "metadata"]},
    )
    data = resp.json()
    assert data["success"] is True


@respx.mock
def test_extract_timeout_handled(client):
    respx.get("https://example.com/slow").mock(side_effect=httpx.TimeoutException("timeout"))
    resp = client.post(
        "/extract",
        json={"url": "https://example.com/slow", "timeout_seconds": 5},
    )
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "FETCH_TIMEOUT"


@respx.mock
def test_extract_body_too_large(client):
    large_body = b"x" * (16 * 1024 * 1024)  # 16 MB > 15 MB default
    respx.get("https://example.com/large").mock(
        return_value=httpx.Response(
            200,
            content=large_body,
            headers={"content-type": "text/html"},
        )
    )
    resp = client.post("/extract", json={"url": "https://example.com/large"})
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "BODY_TOO_LARGE"


@respx.mock
def test_extract_unsupported_content_type(client):
    respx.get("https://example.com/video.mp4").mock(
        return_value=httpx.Response(
            200,
            content=b"\x00\x01\x02",
            headers={"content-type": "video/mp4"},
        )
    )
    resp = client.post("/extract", json={"url": "https://example.com/video.mp4"})
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "UNSUPPORTED_CONTENT_TYPE"
