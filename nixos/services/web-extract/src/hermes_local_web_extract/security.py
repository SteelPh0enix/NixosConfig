"""SSRF protection and URL validation."""

import ipaddress
import socket
from urllib.parse import urljoin, urlparse

from hermes_local_web_extract.errors import BlockedAddressError, InvalidURLError

_MAX_URL_LENGTH = 2048

# Private, loopback, link-local, and reserved ranges to block
_BLOCKED_NETWORKS = [
    ipaddress.ip_network("127.0.0.0/8"),  # IPv4 loopback
    ipaddress.ip_network("10.0.0.0/8"),  # RFC 1918
    ipaddress.ip_network("172.16.0.0/12"),  # RFC 1918
    ipaddress.ip_network("192.168.0.0/16"),  # RFC 1918
    ipaddress.ip_network("169.254.0.0/16"),  # Link-local / cloud metadata
    ipaddress.ip_network("100.64.0.0/10"),  # Shared address space (RFC 6598)
    ipaddress.ip_network("192.0.0.0/24"),  # IETF protocol assignments
    ipaddress.ip_network("192.0.2.0/24"),  # TEST-NET-1
    ipaddress.ip_network("198.51.100.0/24"),  # TEST-NET-2
    ipaddress.ip_network("203.0.113.0/24"),  # TEST-NET-3
    ipaddress.ip_network("240.0.0.0/4"),  # Reserved
    ipaddress.ip_network("0.0.0.0/8"),  # "This" network
    ipaddress.ip_network("::1/128"),  # IPv6 loopback
    ipaddress.ip_network("fc00::/7"),  # IPv6 unique local
    ipaddress.ip_network("fe80::/10"),  # IPv6 link-local
    ipaddress.ip_network("::ffff:0:0/96"),  # IPv4-mapped IPv6
]


def is_ip_blocked(addr: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    """Return True if the IP address falls within any blocked network range."""
    for network in _BLOCKED_NETWORKS:
        try:
            if addr in network:
                return True
        except TypeError:
            continue
    return False


def _resolve_and_check(hostname: str, allow_private: bool) -> None:
    """Resolve hostname to IP(s) and block private/reserved ranges."""
    try:
        results = socket.getaddrinfo(hostname, None, proto=socket.IPPROTO_TCP)
    except socket.gaierror as exc:
        raise InvalidURLError(f"Could not resolve hostname '{hostname}': {exc}") from exc

    if not results:
        # Empty result list means no addresses — treat as unresolvable rather than silently passing.
        raise InvalidURLError(f"Hostname '{hostname}' resolved to no addresses.")

    for _family, _type, _proto, _canonname, sockaddr in results:
        ip_str = sockaddr[0]
        try:
            addr = ipaddress.ip_address(ip_str)
        except ValueError:
            continue

        if allow_private:
            continue

        if is_ip_blocked(addr):
            raise BlockedAddressError(
                f"URL resolves to a blocked/private address ({ip_str}). "
                "Set LOCAL_EXTRACT_ALLOW_PRIVATE_NETWORKS=true to allow (not recommended)."
            )


def validate_url(url: str, allow_private: bool = False) -> str:
    """
    Validate and sanitise a URL for safe fetching.

    Raises InvalidURLError or BlockedAddressError on failure.
    Returns the normalised URL string.
    """
    if not url or not isinstance(url, str):
        raise InvalidURLError("URL must be a non-empty string.")

    url = url.strip()

    if len(url) > _MAX_URL_LENGTH:
        raise InvalidURLError(f"URL exceeds maximum length of {_MAX_URL_LENGTH} characters.")

    try:
        parsed = urlparse(url)
    except Exception as exc:
        raise InvalidURLError(f"Could not parse URL: {exc}") from exc

    if parsed.scheme not in ("http", "https"):
        raise InvalidURLError(
            f"Only http and https URLs are allowed. Got scheme: '{parsed.scheme or '(none)'}'."
        )

    # Reject URLs with embedded credentials (risk of credential leakage in logs)
    if parsed.username or parsed.password:
        raise InvalidURLError("URLs with embedded credentials are not allowed.")

    hostname = parsed.hostname
    if not hostname:
        raise InvalidURLError("URL has no hostname.")

    # Try to parse it as a literal IP first
    try:
        addr = ipaddress.ip_address(hostname)
        if not allow_private and is_ip_blocked(addr):
            raise BlockedAddressError(f"URL points to a blocked/private IP address ({hostname}).")
    except ValueError:
        # Not a literal IP — resolve it
        _resolve_and_check(hostname, allow_private)

    return url


def resolve_redirect(location: str, current_url: str) -> str:
    """
    Resolve a Location header value against the current URL.

    Handles relative (/path), protocol-relative (//host/path), and absolute URLs.
    Must be called before validate_redirect_url so that relative redirects get a
    full scheme+host before SSRF validation.
    """
    return urljoin(current_url, location)


def validate_redirect_url(url: str, allow_private: bool = False) -> str:
    """Re-validate every URL in a redirect chain."""
    return validate_url(url, allow_private=allow_private)
