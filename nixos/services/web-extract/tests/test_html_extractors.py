"""Tests for HTML extractor modules."""

from hermes_local_web_extract.extractors.html_fallback import FallbackExtractor
from hermes_local_web_extract.extractors.html_readability import ReadabilityExtractor
from hermes_local_web_extract.extractors.html_trafilatura import TrafilaturaExtractor

_SIMPLE_HTML = b"""
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Test Article</title>
  <meta name="description" content="A test description.">
  <meta name="author" content="Test Author">
</head>
<body>
  <header><nav>Navigation</nav></header>
  <main>
    <article>
      <h1>Test Heading</h1>
      <p>This is the first paragraph of the article. It contains enough content
      to be considered a valid extraction result for testing purposes.</p>
      <p>Second paragraph with more content to ensure quality thresholds are met.</p>
    </article>
  </main>
  <footer>Footer content</footer>
  <script>var x = 1;</script>
</body>
</html>
"""


def test_trafilatura_extracts_text():
    result = TrafilaturaExtractor().extract(_SIMPLE_HTML, "https://example.com/", "text/html")
    assert result.text is not None
    assert len(result.text) > 20


def test_trafilatura_extracts_markdown():
    result = TrafilaturaExtractor().extract(_SIMPLE_HTML, "https://example.com/", "text/html")
    assert result.markdown is not None
    assert len(result.markdown) > 20


def test_readability_extracts_text():
    result = ReadabilityExtractor().extract(_SIMPLE_HTML, "https://example.com/", "text/html")
    assert result.text is not None
    assert "paragraph" in result.text.lower()


def test_readability_extracts_title():
    result = ReadabilityExtractor().extract(_SIMPLE_HTML, "https://example.com/", "text/html")
    assert result.title == "Test Article"


def test_readability_extracts_description():
    result = ReadabilityExtractor().extract(_SIMPLE_HTML, "https://example.com/", "text/html")
    assert result.description == "A test description."


def test_fallback_extracts_text():
    result = FallbackExtractor().extract(_SIMPLE_HTML, "https://example.com/", "text/html")
    assert result.text is not None
    assert len(result.text) > 10


def test_fallback_excludes_scripts():
    result = FallbackExtractor().extract(_SIMPLE_HTML, "https://example.com/", "text/html")
    assert "var x = 1" not in (result.text or "")
    assert "var x = 1" not in (result.markdown or "")


def test_readability_excludes_scripts():
    result = ReadabilityExtractor().extract(_SIMPLE_HTML, "https://example.com/", "text/html")
    assert "var x = 1" not in (result.text or "")


def test_empty_html_returns_no_crash():
    for extractor in [TrafilaturaExtractor(), ReadabilityExtractor(), FallbackExtractor()]:
        result = extractor.extract(b"<html></html>", "https://example.com/", "text/html")
        assert result is not None
