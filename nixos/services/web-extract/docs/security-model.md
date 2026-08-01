# Security Model

## Design philosophy

hermes-local-web-extract is designed to be safe to run locally without requiring network isolation beyond what you already have. The service operates on the principle of least privilege: it only needs to make outbound HTTP/HTTPS requests to fetch content, and it does so with strict guardrails.

## SSRF protection

Server-Side Request Forgery (SSRF) is the primary threat for a service that fetches arbitrary URLs on behalf of callers. Without protection, a malicious or misconfigured caller could use this service to probe internal infrastructure, access cloud metadata endpoints, or reach services on private networks.

The following ranges are blocked by default:

| Range | Purpose |
|-------|---------|
| `127.0.0.0/8` | IPv4 loopback |
| `10.0.0.0/8` | RFC 1918 private |
| `172.16.0.0/12` | RFC 1918 private |
| `192.168.0.0/16` | RFC 1918 private |
| `169.254.0.0/16` | Link-local and cloud metadata (AWS IMDSv1/v2, GCP, Azure) |
| `100.64.0.0/10` | Shared address space (RFC 6598) |
| `::1/128` | IPv6 loopback |
| `fc00::/7` | IPv6 unique local |
| `fe80::/10` | IPv6 link-local |

The `LOCAL_EXTRACT_ALLOW_PRIVATE_NETWORKS=true` flag disables this protection. Only use it on isolated, trusted networks. The risk is clearly documented in `.env.example`.

## Redirect validation

Every redirect in a chain is re-validated before following it. A redirect to a blocked address raises `BLOCKED_PRIVATE_ADDRESS` even if the initial URL was public.

Non-HTTP/HTTPS redirect schemes are rejected.

## URL validation

- Only `http://` and `https://` schemes are allowed.
- URLs with embedded credentials (`user:pass@host`) are rejected to prevent credential leakage in logs.
- URLs longer than 2048 characters are rejected.
- The hostname is resolved before connecting, and the resolved IP is checked against blocked ranges.

## Rate limiting

The in-memory sliding-window rate limiter limits requests per client IP. The default is 60 requests/minute. The limit is tunable via `LOCAL_EXTRACT_RATE_LIMIT_PER_MINUTE`.

By default, the service uses `request.client.host` as the client key. If you run behind a trusted reverse proxy, set `LOCAL_EXTRACT_TRUST_PROXY_HEADERS=true` to use `X-Forwarded-For`.

**Note:** The rate limiter is in-process and does not persist across restarts. It is not a substitute for network-level rate limiting in a multi-tenant deployment.

## Timeouts and body limits

| Limit | Default | Env variable |
|-------|---------|--------------|
| Request timeout | 20 seconds | `LOCAL_EXTRACT_TIMEOUT_SECONDS` |
| Hard timeout cap | 60 seconds | `LOCAL_EXTRACT_MAX_TIMEOUT_SECONDS` |
| Max response body | 15 MB | `LOCAL_EXTRACT_MAX_BODY_MB` |
| Max PDF size | 20 MB | `LOCAL_EXTRACT_MAX_PDF_MB` |
| Max redirects | 5 | `LOCAL_EXTRACT_MAX_REDIRECTS` |
| Max extracted chars | 200,000 | `LOCAL_EXTRACT_MAX_CONTENT_CHARS` |

## Logging privacy

- Full URLs are not logged by default because they may contain tokens or sensitive query parameters. Set `LOCAL_EXTRACT_LOG_FULL_URLS=true` only for debugging.
- Request bodies are never logged.
- Logs include: method, path, HTTP status, elapsed milliseconds, extractor name, and domain only.

## No telemetry

This service contains no telemetry, analytics, tracking, or external callbacks of any kind. No data leaves your machine except the outbound HTTP request to fetch the target URL.

## No stored secrets

No API keys, tokens, or credentials are required or stored by this service.

## Docker security

The provided `docker-compose.yml` applies:

- `no-new-privileges:true` — prevents privilege escalation inside the container.
- `read_only: true` — mounts the container filesystem read-only.
- `tmpfs: /tmp` — writable tmpfs for temporary files.
- `cap_drop: ALL` — drops all Linux capabilities.
- Non-root user (`UID 1001`).

## Browser mode risk

Enabling browser mode (`LOCAL_EXTRACT_BROWSER_ENABLED=true`) runs a headless Chromium process. Browser processes have a larger attack surface. Only enable it when:

- You trust all callers.
- You specifically need JavaScript rendering.
- You understand that Playwright/Chromium has its own security update cycle.

## CAPTCHA bypass and stealth scraping

This project intentionally does not implement CAPTCHA bypass, stealth scraping, anti-bot evasion, proxy rotation, or login session hijacking. These techniques create legal and ethical risk and encourage abuse. They are out of scope by design.

## Disclosure

See [SECURITY.md](../SECURITY.md) for the vulnerability disclosure process.
