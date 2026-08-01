"""Optional in-memory TTL cache for extraction results."""

import hashlib
import json
from typing import Any

from cachetools import TTLCache

_cache: TTLCache | None = None
_enabled: bool = False


def _make_key(url: str, options: dict[str, Any]) -> str:
    payload = json.dumps({"url": url, **options}, sort_keys=True)
    return hashlib.sha256(payload.encode()).hexdigest()


def init_cache(enabled: bool, ttl_seconds: int, maxsize: int = 512) -> None:
    global _cache, _enabled
    _enabled = enabled
    if enabled:
        _cache = TTLCache(maxsize=maxsize, ttl=ttl_seconds)


def cache_get(url: str, options: dict[str, Any]) -> Any | None:
    if not _enabled or _cache is None:
        return None
    key = _make_key(url, options)
    return _cache.get(key)


def cache_set(url: str, options: dict[str, Any], value: Any) -> None:
    if not _enabled or _cache is None:
        return
    key = _make_key(url, options)
    _cache[key] = value
