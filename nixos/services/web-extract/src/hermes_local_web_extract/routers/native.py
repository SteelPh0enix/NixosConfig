"""Native /extract endpoint."""

import logging

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from hermes_local_web_extract.config import Settings, get_settings
from hermes_local_web_extract.errors import ExtractException
from hermes_local_web_extract.models import (
    ErrorResponse,
    ExtractError,
    ExtractErrorCode,
    ExtractRequest,
    ExtractResponse,
)
from hermes_local_web_extract.pipeline import run_extraction
from hermes_local_web_extract.rate_limit import get_limiter

logger = logging.getLogger(__name__)

router = APIRouter(tags=["extract"])


@router.post(
    "/extract",
    response_model=ExtractResponse,
    responses={
        400: {"model": ErrorResponse},
        429: {"model": ErrorResponse},
        500: {"model": ErrorResponse},
    },
    summary="Extract content from a URL",
)
async def extract(
    request: Request,
    body: ExtractRequest,
    settings: Settings = Depends(get_settings),
) -> JSONResponse:
    limiter = get_limiter()
    try:
        limiter.check(request)
    except ExtractException as exc:
        return JSONResponse(
            status_code=429,
            content=ErrorResponse(
                error=ExtractError(code=exc.code, message=exc.message)
            ).model_dump(),
        )

    try:
        response = await run_extraction(body, settings)
        return JSONResponse(content=response.model_dump())
    except ExtractException as exc:
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
    except Exception:
        logger.exception("Unexpected error during extraction")
        return JSONResponse(
            status_code=500,
            content=ErrorResponse(
                error=ExtractError(
                    code=ExtractErrorCode.INTERNAL_ERROR,
                    message="An unexpected internal error occurred.",
                )
            ).model_dump(),
        )
