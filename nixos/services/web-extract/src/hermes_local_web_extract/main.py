"""Application entry point and FastAPI app factory."""

import logging
import time
import uuid

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from hermes_local_web_extract import __version__
from hermes_local_web_extract.cache import init_cache
from hermes_local_web_extract.config import get_settings
from hermes_local_web_extract.errors import ExtractException
from hermes_local_web_extract.logging_config import configure_logging
from hermes_local_web_extract.models import ErrorResponse, ExtractError, ExtractErrorCode
from hermes_local_web_extract.routers import firecrawl_compat, health, native

logger = logging.getLogger(__name__)


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings.log_level)
    init_cache(
        enabled=settings.cache_enabled,
        ttl_seconds=settings.cache_ttl_seconds,
    )

    app = FastAPI(
        title="hermes-local-web-extract",
        description=(
            "Free, self-hosted, local web extraction backend for Hermes Agent. "
            "No paid API key required."
        ),
        version=__version__,
        docs_url="/docs",
        redoc_url="/redoc",
        openapi_url="/openapi.json",
    )

    # Request ID and timing middleware
    @app.middleware("http")
    async def request_context_middleware(request: Request, call_next):  # type: ignore[no-untyped-def]
        request_id = str(uuid.uuid4())[:8]
        request.state.request_id = request_id
        start = time.monotonic()
        response = await call_next(request)
        elapsed_ms = int((time.monotonic() - start) * 1000)
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Elapsed-Ms"] = str(elapsed_ms)
        logger.debug(
            "method=%s path=%s status=%d elapsed_ms=%d request_id=%s",
            request.method,
            request.url.path,
            response.status_code,
            elapsed_ms,
            request_id,
        )
        return response

    # Global exception handler — never expose stack traces
    @app.exception_handler(ExtractException)
    async def extract_exception_handler(request: Request, exc: ExtractException) -> JSONResponse:
        status = 400
        if exc.code == ExtractErrorCode.RATE_LIMITED:
            status = 429
        elif exc.code == ExtractErrorCode.INTERNAL_ERROR:
            status = 500
        return JSONResponse(
            status_code=status,
            content=ErrorResponse(
                error=ExtractError(code=exc.code, message=exc.message)
            ).model_dump(),
        )

    @app.exception_handler(Exception)
    async def generic_exception_handler(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("Unhandled exception for %s %s", request.method, request.url.path)
        return JSONResponse(
            status_code=500,
            content=ErrorResponse(
                error=ExtractError(
                    code=ExtractErrorCode.INTERNAL_ERROR,
                    message="An internal server error occurred.",
                )
            ).model_dump(),
        )

    app.include_router(health.router)
    app.include_router(native.router)
    app.include_router(firecrawl_compat.router)

    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn

    s = get_settings()
    uvicorn.run(
        "hermes_local_web_extract.main:app",
        host=s.host,
        port=s.port,
        log_level=s.log_level.lower(),
        workers=1,
    )
