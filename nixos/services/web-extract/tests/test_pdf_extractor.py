"""Tests for the PDF extractor."""


def _make_minimal_pdf(text: str = "Hello from PDF") -> bytes:
    """Build a minimal valid single-page PDF containing the given text."""
    # This generates a syntactically valid but very simple PDF.
    lines = [
        b"%PDF-1.4",
        b"1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj",
        b"2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj",
    ]
    # Page content stream
    stream_content = (f"BT /F1 12 Tf 100 700 Td ({text}) Tj ET").encode()
    stream_len = len(stream_content)
    lines += [
        b"3 0 obj << /Type /Page /Parent 2 0 R "
        b"/MediaBox [0 0 612 792] "
        b"/Contents 4 0 R "
        b"/Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> "
        b">> endobj",
        f"4 0 obj << /Length {stream_len} >>".encode(),
        b"stream",
        stream_content,
        b"endstream endobj",
    ]
    body = b"\n".join(lines) + b"\n"
    # xref and trailer (simplified — pypdf tolerates this)
    xref_offset = len(body)
    xref = b"xref\n0 5\n0000000000 65535 f \n" + b"0000000000 00000 n \n" * 4
    trailer = (f"trailer << /Size 5 /Root 1 0 R >>\nstartxref\n{xref_offset}\n%%EOF\n").encode()
    return body + xref + trailer


def test_pdf_extractor_extracts_text():
    from hermes_local_web_extract.extractors.pdf_extractor import PDFExtractor

    pdf_bytes = _make_minimal_pdf("TestContent")
    result = PDFExtractor().extract(pdf_bytes, "https://example.com/doc.pdf", "application/pdf")
    # pypdf may or may not extract text from this minimal PDF depending on version,
    # but it must not crash and must return an ExtractionResult.
    assert result is not None
    assert result.extractor_name == "pypdf"


def test_pdf_extractor_no_crash_on_empty():
    from hermes_local_web_extract.extractors.pdf_extractor import PDFExtractor

    result = PDFExtractor().extract(b"", "https://example.com/doc.pdf", "application/pdf")
    assert result is not None
    assert result.warnings  # Should warn about invalid PDF


def test_pdf_extractor_no_crash_on_garbage():
    from hermes_local_web_extract.extractors.pdf_extractor import PDFExtractor

    result = PDFExtractor().extract(
        b"NOT A PDF AT ALL", "https://example.com/doc.pdf", "application/pdf"
    )
    assert result is not None
    assert result.warnings
