from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="LOCAL_EXTRACT_",
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # Server
    host: str = Field(default="0.0.0.0")
    port: int = Field(default=8090, ge=1, le=65535)

    # Logging
    log_level: str = Field(default="INFO")
    log_full_urls: bool = Field(default=False)

    # Security
    allow_private_networks: bool = Field(default=False)
    trust_proxy_headers: bool = Field(default=False)

    # Fetch limits
    max_body_mb: int = Field(default=15, ge=1, le=200)
    max_pdf_mb: int = Field(default=20, ge=1, le=200)
    timeout_seconds: int = Field(default=20, ge=1, le=60)
    max_timeout_seconds: int = Field(default=60, ge=1, le=300)
    max_redirects: int = Field(default=5, ge=0, le=20)
    max_content_chars: int = Field(default=200_000, ge=1000)

    # Rate limiting & concurrency
    rate_limit_per_minute: int = Field(default=60, ge=1, le=10_000)
    concurrency: int = Field(default=8, ge=1, le=64)

    # Cache
    cache_enabled: bool = Field(default=False)
    cache_ttl_seconds: int = Field(default=3600, ge=60)
    cache_backend: str = Field(default="memory")

    # Browser
    browser_enabled: bool = Field(default=False)

    # Robots.txt
    respect_robots_txt: bool = Field(default=False)

    @field_validator("log_level")
    @classmethod
    def validate_log_level(cls, v: str) -> str:
        allowed = {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}
        upper = v.upper()
        if upper not in allowed:
            raise ValueError(f"log_level must be one of {allowed}")
        return upper

    @property
    def max_body_bytes(self) -> int:
        return self.max_body_mb * 1024 * 1024

    @property
    def max_pdf_bytes(self) -> int:
        return self.max_pdf_mb * 1024 * 1024

    @property
    def user_agent(self) -> str:
        from hermes_local_web_extract import __version__

        return (
            f"hermes-local-web-extract/{__version__} "
            "(+https://github.com/gopalasubramanium/web_extract)"
        )


_settings: Settings | None = None


def get_settings() -> Settings:
    global _settings
    if _settings is None:
        _settings = Settings()
    return _settings
