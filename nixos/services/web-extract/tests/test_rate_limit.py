"""Tests for the in-memory rate limiter."""

import os

import pytest


def test_rate_limit_allows_within_limit():
    from unittest.mock import MagicMock

    from hermes_local_web_extract.rate_limit import SlidingWindowRateLimiter

    limiter = SlidingWindowRateLimiter(requests_per_minute=5, trust_proxy=False)
    request = MagicMock()
    request.client.host = "10.0.0.1"
    request.headers = {}

    for _ in range(5):
        limiter.check(request)  # Should not raise


def test_rate_limit_blocks_when_exceeded():
    from unittest.mock import MagicMock

    from hermes_local_web_extract.errors import RateLimitedError
    from hermes_local_web_extract.rate_limit import SlidingWindowRateLimiter

    limiter = SlidingWindowRateLimiter(requests_per_minute=3, trust_proxy=False)
    request = MagicMock()
    request.client.host = "10.0.0.2"
    request.headers = {}

    for _ in range(3):
        limiter.check(request)

    with pytest.raises(RateLimitedError):
        limiter.check(request)


def test_rate_limit_per_client_independent():
    from unittest.mock import MagicMock

    from hermes_local_web_extract.rate_limit import SlidingWindowRateLimiter

    limiter = SlidingWindowRateLimiter(requests_per_minute=2, trust_proxy=False)

    req_a = MagicMock()
    req_a.client.host = "1.2.3.4"
    req_a.headers = {}

    req_b = MagicMock()
    req_b.client.host = "5.6.7.8"
    req_b.headers = {}

    limiter.check(req_a)
    limiter.check(req_a)
    limiter.check(req_b)  # Different client — should not be affected by A's count
    limiter.check(req_b)


def test_rate_limit_http_endpoint(client):
    """Rate limit on the API endpoint returns 429 when exceeded."""

    os.environ["LOCAL_EXTRACT_RATE_LIMIT_PER_MINUTE"] = "2"
    import hermes_local_web_extract.config as cfg
    import hermes_local_web_extract.rate_limit as rl

    cfg._settings = None
    rl._limiter = None

    from fastapi.testclient import TestClient

    from hermes_local_web_extract.main import create_app

    app = create_app()
    with TestClient(app, raise_server_exceptions=False) as c:
        # Make 3 requests (limit is 2) with an invalid URL so we get past rate limit check
        responses = []
        for _ in range(3):
            r = c.post("/extract", json={"url": "file:///etc/passwd"})
            responses.append(r.status_code)

    # At least one should be 429
    assert 429 in responses

    # Restore
    os.environ["LOCAL_EXTRACT_RATE_LIMIT_PER_MINUTE"] = "10000"
    cfg._settings = None
    rl._limiter = None
