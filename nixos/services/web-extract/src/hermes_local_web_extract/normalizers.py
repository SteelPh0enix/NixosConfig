"""Content normalisation: whitespace, length, encoding."""

import re
import unicodedata


def clean_text(text: str, max_chars: int | None = None) -> tuple[str, list[str]]:
    """
    Normalise extracted text.

    Returns (cleaned_text, warnings).
    """
    warnings: list[str] = []
    if not text:
        return "", warnings

    # Remove null bytes and ASCII control characters (keep newlines and tabs)
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text)

    # Normalise unicode to NFC
    text = unicodedata.normalize("NFC", text)

    # Collapse runs of spaces/tabs to a single space (but keep newlines)
    text = re.sub(r"[ \t]+", " ", text)

    # Collapse more than 2 consecutive blank lines to 2
    text = re.sub(r"\n{3,}", "\n\n", text)

    text = text.strip()

    if max_chars and len(text) > max_chars:
        text = text[:max_chars]
        warnings.append(f"Content was truncated to {max_chars} characters.")

    return text, warnings


def clean_markdown(markdown: str, max_chars: int | None = None) -> tuple[str, list[str]]:
    """Normalise markdown output, preserving code blocks and tables."""
    warnings: list[str] = []
    if not markdown:
        return "", warnings

    # Remove null bytes and control characters outside code blocks
    lines = markdown.split("\n")
    in_code_block = False
    cleaned: list[str] = []
    for line in lines:
        if line.startswith("```"):
            in_code_block = not in_code_block
        if not in_code_block:
            line = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", line)
            line = re.sub(r"[ \t]+$", "", line)  # strip trailing whitespace
        cleaned.append(line)

    markdown = "\n".join(cleaned)

    # Collapse excessive blank lines (but not inside code blocks)
    markdown = re.sub(r"\n{4,}", "\n\n\n", markdown)

    markdown = markdown.strip()

    if max_chars and len(markdown) > max_chars:
        markdown = markdown[:max_chars]
        warnings.append(f"Markdown content was truncated to {max_chars} characters.")

    return markdown, warnings
