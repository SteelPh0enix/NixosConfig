"""Base extractor protocol."""

from dataclasses import dataclass, field
from typing import Protocol


@dataclass
class ExtractionResult:
    text: str | None = None
    markdown: str | None = None
    html: str | None = None
    title: str | None = None
    description: str | None = None
    author: str | None = None
    date: str | None = None
    site_name: str | None = None
    language: str | None = None
    links: list[str] = field(default_factory=list)
    images: list[str] = field(default_factory=list)
    extractor_name: str = "unknown"
    warnings: list[str] = field(default_factory=list)


class BaseExtractor(Protocol):
    def extract(self, content: bytes, url: str, content_type: str) -> ExtractionResult: ...
