"""Shared test fixtures."""

import os

import pytest
from fastapi.testclient import TestClient

# Force safe defaults for all tests
os.environ.setdefault("LOCAL_EXTRACT_ALLOW_PRIVATE_NETWORKS", "false")
os.environ.setdefault("LOCAL_EXTRACT_CACHE_ENABLED", "false")
os.environ.setdefault("LOCAL_EXTRACT_BROWSER_ENABLED", "false")
os.environ.setdefault("LOCAL_EXTRACT_RATE_LIMIT_PER_MINUTE", "10000")


@pytest.fixture(scope="session")
def client():
    # Reset singleton settings so env overrides take effect
    import hermes_local_web_extract.config as cfg
    import hermes_local_web_extract.rate_limit as rl

    cfg._settings = None
    rl._limiter = None

    from hermes_local_web_extract.main import create_app

    app = create_app()
    with TestClient(app, raise_server_exceptions=False) as c:
        yield c
