"""Tests for SSRF protection and URL validation."""

import ipaddress

import pytest

from hermes_local_web_extract.errors import BlockedAddressError, InvalidURLError
from hermes_local_web_extract.security import is_ip_blocked, validate_url

# --- Unit tests for is_ip_blocked ---


def test_loopback_blocked():
    assert is_ip_blocked(ipaddress.ip_address("127.0.0.1")) is True


def test_localhost_variant_blocked():
    assert is_ip_blocked(ipaddress.ip_address("127.0.0.2")) is True


def test_rfc1918_10_blocked():
    assert is_ip_blocked(ipaddress.ip_address("10.0.0.1")) is True


def test_rfc1918_172_blocked():
    assert is_ip_blocked(ipaddress.ip_address("172.16.0.1")) is True
    assert is_ip_blocked(ipaddress.ip_address("172.31.255.255")) is True


def test_rfc1918_192_blocked():
    assert is_ip_blocked(ipaddress.ip_address("192.168.1.1")) is True


def test_cloud_metadata_blocked():
    assert is_ip_blocked(ipaddress.ip_address("169.254.169.254")) is True


def test_ipv6_loopback_blocked():
    assert is_ip_blocked(ipaddress.ip_address("::1")) is True


def test_ipv6_unique_local_blocked():
    assert is_ip_blocked(ipaddress.ip_address("fc00::1")) is True
    assert is_ip_blocked(ipaddress.ip_address("fd12:3456:789a::1")) is True


def test_public_ip_not_blocked():
    assert is_ip_blocked(ipaddress.ip_address("8.8.8.8")) is False
    assert is_ip_blocked(ipaddress.ip_address("1.1.1.1")) is False


# --- validate_url tests ---


def test_file_scheme_rejected():
    with pytest.raises(InvalidURLError, match="Only http and https"):
        validate_url("file:///etc/passwd")


def test_ftp_scheme_rejected():
    with pytest.raises(InvalidURLError):
        validate_url("ftp://example.com/file.txt")


def test_empty_url_rejected():
    with pytest.raises(InvalidURLError):
        validate_url("")


def test_url_too_long_rejected():
    with pytest.raises(InvalidURLError, match="maximum length"):
        validate_url("https://example.com/" + "a" * 3000)


def test_url_with_credentials_rejected():
    with pytest.raises(InvalidURLError, match="credentials"):
        validate_url("https://user:pass@example.com/")


def test_literal_loopback_ip_rejected():
    with pytest.raises(BlockedAddressError):
        validate_url("http://127.0.0.1/")


def test_literal_private_ip_rejected():
    with pytest.raises(BlockedAddressError):
        validate_url("http://192.168.1.100/")


def test_cloud_metadata_literal_rejected():
    with pytest.raises(BlockedAddressError):
        validate_url("http://169.254.169.254/latest/meta-data/")


def test_private_allowed_when_flag_set():
    # Should not raise when allow_private=True
    # Note: this will try to connect if it passes; mock DNS in real scenario.
    # We only test the IP literal path here.
    result = validate_url("http://192.168.1.1/", allow_private=True)
    assert result.startswith("http://")


def test_valid_public_url_passes():
    # Bypasses DNS resolution for literal IPs; for hostnames DNS is called.
    # Use a literal public IP to avoid DNS in unit tests.
    result = validate_url("https://8.8.8.8/")
    assert result == "https://8.8.8.8/"
