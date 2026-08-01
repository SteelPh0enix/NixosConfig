"""Health and readiness endpoints."""

from fastapi import APIRouter

from hermes_local_web_extract import __version__
from hermes_local_web_extract.models import HealthResponse

router = APIRouter(tags=["health"])


@router.get("/healthz", response_model=HealthResponse, summary="Liveness probe")
async def healthz() -> HealthResponse:
    """Returns 200 when the server process is running."""
    return HealthResponse(success=True, status="ok", version=__version__)


@router.get("/readyz", response_model=HealthResponse, summary="Readiness probe")
async def readyz() -> HealthResponse:
    """Returns 200 when the server is ready to accept requests."""
    return HealthResponse(success=True, status="ok", version=__version__)


@router.get("/v1/health", response_model=HealthResponse, summary="Firecrawl-compatible health")
async def v1_health() -> HealthResponse:
    """Firecrawl-compatible health endpoint."""
    return HealthResponse(success=True, status="ok", version=__version__)
