# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | Yes       |

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Please report security issues by emailing the maintainer directly or by using GitHub's private security advisory feature:

1. Go to the repository on GitHub.
2. Click **Security** → **Advisories** → **New draft security advisory**.
3. Describe the vulnerability, steps to reproduce, and impact.

We aim to acknowledge reports within 3 business days and to provide a fix or mitigation within 14 days for critical issues.

## Security design

hermes-local-web-extract is designed to run as a **local, self-hosted service**. Its threat model assumes:

- The service is not exposed to the public internet.
- Callers are trusted agents or applications on the same host or trusted network.
- The operator has read and understood the configuration.

### SSRF protection

By default, the service blocks requests to private, loopback, link-local, and cloud metadata addresses. This prevents a compromised or malicious caller from using the service to probe internal infrastructure.

See [docs/security-model.md](docs/security-model.md) for full details.

### Secrets

- No API keys, tokens, or secrets are required or stored by this project.
- No telemetry is collected.
- Request bodies are not logged.

### Docker security

The Docker image runs as a non-root user, drops all Linux capabilities, and mounts the filesystem read-only with a tmpfs for `/tmp`.

## Known limitations

- This service trusts that the operator has secured it at the network level. If you expose it to the internet without authentication, any caller can use it to fetch arbitrary public URLs.
- Rate limiting is in-memory and per-process. It is not suitable as the sole protection against abuse at scale.
- Browser mode (Crawl4AI) requires additional trust as it runs a headless browser process.
