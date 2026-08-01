"""Tests for the Firecrawl-compatible /v1/scrape endpoint."""

import httpx
import respx

_SAMPLE_HTML = b"""<!DOCTYPE html>
<html><head><title>Firecrawl Compat Test</title></head>
<body><article>
<h1>Test Article</h1>
<p>This article has sufficient content to pass extraction quality checks during testing.</p>
<p>Second paragraph of article content for the firecrawl compatibility endpoint tests.</p>
</article></body></html>"""


@respx.mock
def test_firecrawl_scrape_success(client):
    respx.get("https://example.com/").mock(
        return_value=httpx.Response(
            200,
            content=_SAMPLE_HTML,
            headers={"content-type": "text/html"},
        )
    )
    resp = client.post(
        "/v1/scrape",
        json={"url": "https://example.com/", "formats": ["markdown", "html"]},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    assert "data" in data
    assert "markdown" in data["data"]
    assert "metadata" in data["data"]


@respx.mock
def test_firecrawl_metadata_shape(client):
    respx.get("https://example.com/meta").mock(
        return_value=httpx.Response(
            200,
            content=_SAMPLE_HTML,
            headers={"content-type": "text/html"},
        )
    )
    resp = client.post(
        "/v1/scrape",
        json={"url": "https://example.com/meta", "formats": ["markdown"]},
    )
    data = resp.json()
    meta = data["data"]["metadata"]
    assert "sourceURL" in meta
    assert "statusCode" in meta


def test_firecrawl_invalid_url(client):
    resp = client.post("/v1/scrape", json={"url": "file:///etc/passwd"})
    assert resp.status_code == 400
    data = resp.json()
    assert data["success"] is False
    assert data["error"]["code"] == "INVALID_URL"


def test_firecrawl_missing_url(client):
    resp = client.post("/v1/scrape", json={})
    assert resp.status_code == 422


@respx.mock
def test_firecrawl_snake_case_fields(client):
    """Ensure snake_case aliases are accepted."""
    respx.get("https://example.com/snake").mock(
        return_value=httpx.Response(
            200,
            content=_SAMPLE_HTML,
            headers={"content-type": "text/html"},
        )
    )
    resp = client.post(
        "/v1/scrape",
        json={
            "url": "https://example.com/snake",
            "formats": ["markdown"],
            "only_main_content": True,
            "timeout": 15000,
        },
    )
    assert resp.status_code == 200
    assert resp.json()["success"] is True


@respx.mock
def test_firecrawl_camelcase_fields(client):
    """Ensure camelCase Firecrawl-style fields are accepted."""
    respx.get("https://example.com/camel").mock(
        return_value=httpx.Response(
            200,
            content=_SAMPLE_HTML,
            headers={"content-type": "text/html"},
        )
    )
    resp = client.post(
        "/v1/scrape",
        json={
            "url": "https://example.com/camel",
            "formats": ["markdown"],
            "onlyMainContent": True,
            "timeout": 10000,
        },
    )
    assert resp.status_code == 200
    assert resp.json()["success"] is True
