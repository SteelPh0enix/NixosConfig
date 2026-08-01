# Stage 1: build — compiles lxml and other C extensions, then discards gcc
FROM python:3.12-slim AS builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libxml2-dev libxslt1-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY requirements.txt pyproject.toml ./
COPY src/ ./src/
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt \
    && pip install --no-cache-dir --prefix=/install --no-deps .


# Stage 2: runtime — no compiler, smaller attack surface
FROM python:3.12-slim

# Runtime shared libraries needed by lxml (no compiler required)
RUN apt-get update \
    && apt-get install -y --no-install-recommends libxml2 libxslt1.1 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd --gid 1001 appgroup \
    && useradd --uid 1001 --gid appgroup --shell /bin/bash --create-home appuser

WORKDIR /app

# Copy compiled dependencies from builder stage
COPY --from=builder /install /usr/local

# Copy application source
COPY src/ ./src/

# Own files by non-root user
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 8090

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8090/healthz')" || exit 1

CMD ["uvicorn", "hermes_local_web_extract.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8090", \
     "--workers", "1", \
     "--log-level", "info"]
