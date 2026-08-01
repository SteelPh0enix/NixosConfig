from enum import StrEnum

from pydantic import BaseModel, Field, field_validator


class RenderJs(StrEnum):
    never = "never"
    auto = "auto"
    always = "always"


class OutputFormat(StrEnum):
    markdown = "markdown"
    text = "text"
    html = "html"
    metadata = "metadata"


class ExtractRequest(BaseModel):
    url: str = Field(..., description="URL to extract content from (http/https only).")
    formats: list[OutputFormat] = Field(
        default=[OutputFormat.markdown, OutputFormat.text, OutputFormat.metadata],
        description="Output formats to include in the response.",
    )
    render_js: RenderJs = Field(
        default=RenderJs.never,
        description="JavaScript rendering mode. 'always'/'auto' require browser profile.",
    )
    timeout_seconds: int = Field(
        default=20,
        ge=1,
        le=300,
        description="Per-request timeout in seconds.",
    )
    include_metadata: bool = Field(default=True)
    include_links: bool = Field(default=False)
    include_images: bool = Field(default=False)
    max_content_chars: int = Field(default=200_000, ge=1000)

    @field_validator("url")
    @classmethod
    def url_not_empty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("url must not be empty")
        return v.strip()


class ExtractMetadata(BaseModel):
    title: str | None = None
    author: str | None = None
    date: str | None = None
    site_name: str | None = None
    language: str | None = None
    content_type: str | None = None
    status_code: int | None = None
    extractor: str | None = None
    elapsed_ms: int | None = None


class ExtractResponse(BaseModel):
    success: bool = True
    url: str
    final_url: str
    title: str | None = None
    description: str | None = None
    markdown: str | None = None
    text: str | None = None
    html: str | None = None
    metadata: ExtractMetadata | None = None
    links: list[str] = Field(default_factory=list)
    images: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class ExtractErrorCode(StrEnum):
    INVALID_URL = "INVALID_URL"
    BLOCKED_PRIVATE_ADDRESS = "BLOCKED_PRIVATE_ADDRESS"
    FETCH_TIMEOUT = "FETCH_TIMEOUT"
    UNSUPPORTED_CONTENT_TYPE = "UNSUPPORTED_CONTENT_TYPE"
    EXTRACTION_FAILED = "EXTRACTION_FAILED"
    RATE_LIMITED = "RATE_LIMITED"
    INTERNAL_ERROR = "INTERNAL_ERROR"
    FETCH_ERROR = "FETCH_ERROR"
    BODY_TOO_LARGE = "BODY_TOO_LARGE"


class ExtractError(BaseModel):
    code: ExtractErrorCode
    message: str


class ErrorResponse(BaseModel):
    success: bool = False
    error: ExtractError


# Firecrawl-compatible models


class FirecrawlScrapeRequest(BaseModel):
    url: str = Field(..., description="URL to scrape.")
    formats: list[str] = Field(default=["markdown"])
    # Accept both camelCase and snake_case
    onlyMainContent: bool = Field(default=True, alias="onlyMainContent")
    only_main_content: bool = Field(default=True)
    timeout: int = Field(default=20_000, description="Timeout in milliseconds.")
    waitFor: int = Field(default=0, alias="waitFor")
    wait_for: int = Field(default=0)

    model_config = {"populate_by_name": True}

    @field_validator("url")
    @classmethod
    def url_not_empty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("url must not be empty")
        return v.strip()

    def effective_only_main_content(self) -> bool:
        return self.onlyMainContent or self.only_main_content

    def timeout_seconds(self) -> int:
        # Firecrawl uses milliseconds; clamp between 1 and 60
        raw = max(1, self.timeout // 1000)
        return min(raw, 60)


class FirecrawlMetadata(BaseModel):
    title: str | None = None
    description: str | None = None
    sourceURL: str | None = None
    url: str | None = None
    statusCode: int | None = None
    contentType: str | None = None
    extractor: str | None = None


class FirecrawlData(BaseModel):
    markdown: str | None = None
    html: str | None = None
    metadata: FirecrawlMetadata | None = None


class FirecrawlScrapeResponse(BaseModel):
    success: bool = True
    data: FirecrawlData


class HealthResponse(BaseModel):
    success: bool = True
    status: str = "ok"
    version: str | None = None
