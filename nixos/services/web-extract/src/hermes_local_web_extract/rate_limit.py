"""Simple in-memory sliding-window rate limiter."""

import time
from collections import deque
from threading import Lock

from fastapi import Request

from hermes_local_web_extract.errors import RateLimitedError


class SlidingWindowRateLimiter:
    """Per-client sliding window rate limiter backed by in-memory deques."""

    def __init__(self, requests_per_minute: int, trust_proxy: bool = False) -> None:
        self._limit = requests_per_minute
        self._window = 60.0
        self._trust_proxy = trust_proxy
        self._clients: dict[str, deque[float]] = {}
        self._lock = Lock()

    def _get_client_key(self, request: Request) -> str:
        if self._trust_proxy:
            forwarded_for = request.headers.get("x-forwarded-for")
            if forwarded_for:
                # Take the first (leftmost) address, which should be the real client
                return forwarded_for.split(",")[0].strip()
        host = request.client.host if request.client else "unknown"
        return host

    def check(self, request: Request) -> None:
        """Raise RateLimitedError if the client has exceeded the rate limit."""
        key = self._get_client_key(request)
        now = time.monotonic()
        cutoff = now - self._window

        with self._lock:
            if key not in self._clients:
                self._clients[key] = deque()

            window = self._clients[key]
            # Evict timestamps outside the window
            while window and window[0] < cutoff:
                window.popleft()

            if len(window) >= self._limit:
                raise RateLimitedError(f"Rate limit of {self._limit} requests/minute exceeded.")

            window.append(now)

    def cleanup_stale(self) -> None:
        """Remove idle clients to prevent unbounded memory growth."""
        now = time.monotonic()
        cutoff = now - self._window
        with self._lock:
            stale = [k for k, dq in self._clients.items() if not dq or dq[-1] < cutoff]
            for k in stale:
                del self._clients[k]


_limiter: SlidingWindowRateLimiter | None = None


def get_limiter() -> SlidingWindowRateLimiter:
    global _limiter
    if _limiter is None:
        from hermes_local_web_extract.config import get_settings

        s = get_settings()
        _limiter = SlidingWindowRateLimiter(
            requests_per_minute=s.rate_limit_per_minute,
            trust_proxy=s.trust_proxy_headers,
        )
    return _limiter
