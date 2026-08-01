"""Text utility helpers."""


def truncate(text: str, max_chars: int) -> tuple[str, bool]:
    """Return (text, was_truncated)."""
    if len(text) <= max_chars:
        return text, False
    return text[:max_chars], True


def is_content_poor(text: str | None, min_chars: int = 50) -> bool:
    """Return True if extracted text is too short to be useful."""
    if not text:
        return True
    return len(text.strip()) < min_chars
