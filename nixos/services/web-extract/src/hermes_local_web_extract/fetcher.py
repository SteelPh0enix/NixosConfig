"""Async HTTP fetcher with SSRF protection and redirect validation."""

import time
from dataclasses import dataclass

import httpx

from hermes_local_web_extract.config import Settings
from hermes_local_web_extract.errors import (
    BlockedAddressError,
    BodyTooLargeError,
    FetchError,
    FetchTimeoutError,
    InvalidURLError,
)
from hermes_local_web_extract.security import (
    resolve_redirect,
    validate_redirect_url,
    validate_url,
)


@dataclass
class FetchResult:
    url: str
    final_url: str
    status_code: int
    headers: dict[str, str]
    content: bytes
    content_type: str
    elapsed_ms: int


def _build_client(settings: Settings) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        follow_redirects=False,  # We handle redirects manually for SSRF checks
        timeout=httpx.Timeout(connect=10.0, read=settings.timeout_seconds, write=10.0, pool=5.0),
        headers={
            "User-Agent": settings.user_agent,
            "Accept": "text/html,application/xhtml+xml,application/pdf,text/plain,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        },
        max_redirects=0,
    )


async def fetch(url: str, settings: Settings, timeout_override: int | None = None) -> FetchResult:
    """
    Fetch a URL with SSRF protection, redirect validation, and body size enforcement.
    """
    allow_private = settings.allow_private_networks
    max_body = settings.max_body_bytes
    max_redirects = settings.max_redirects

    # Explicit None check so that timeout_override=0 is not silently ignored.
    # (ge=1 on the model prevents 0 via API, but defence-in-depth here.)
    if timeout_override is not None:
        timeout_secs = min(timeout_override, settings.max_timeout_seconds)
    else:
        timeout_secs = min(settings.timeout_seconds, settings.max_timeout_seconds)

    validated_url = validate_url(url, allow_private=allow_private)
    current_url = validated_url
    redirects_followed = 0
    start = time.monotonic()

    async with _build_client(settings) as client:
        while True:
            try:
                response = await client.get(
                    current_url,
                    timeout=httpx.Timeout(
                        connect=10.0, read=float(timeout_secs), write=10.0, pool=5.0
                    ),
                )
            except httpx.TimeoutException as exc:
                # Omit current_url from the message — it may be a redirect target
                # containing tokens or sensitive path components.
                raise FetchTimeoutError(f"Request timed out after {timeout_secs}s.") from exc
            except httpx.RequestError as exc:
                raise FetchError(f"Network error fetching URL: {exc}") from exc

            if response.is_redirect:
                if redirects_followed >= max_redirects:
                    raise FetchError(f"Too many redirects (max {max_redirects}).")
                location = response.headers.get("location", "")
                if not location:
                    raise FetchError("Redirect with no Location header.")

                # Resolve relative Location headers (e.g. "/path", "//host/path") against
                # current_url before SSRF validation. Relative redirects are valid HTTP and
                # common in practice; without this they would be rejected as malformed URLs.
                resolved_location = resolve_redirect(location, current_url)

                # Re-validate each redirect target for SSRF
                try:
                    resolved_location = validate_redirect_url(
                        resolved_location, allow_private=allow_private
                    )
                except (InvalidURLError, BlockedAddressError):
                    raise

                redirects_followed += 1
                current_url = resolved_location
                continue

            # Non-redirect: read body with size limit
            content = b""
            async for chunk in response.aiter_bytes(chunk_size=65536):
                content += chunk
                if len(content) > max_body:
                    raise BodyTooLargeError(
                        f"Response body exceeds {settings.max_body_mb} MB limit."
                    )

            elapsed_ms = int((time.monotonic() - start) * 1000)
            content_type = response.headers.get("content-type", "application/octet-stream")

            return FetchResult(
                url=url,
                final_url=str(response.url),
                status_code=response.status_code,
                headers=dict(response.headers),
                content=content,
                content_type=content_type.split(";")[0].strip().lower(),
                elapsed_ms=elapsed_ms,
            )
