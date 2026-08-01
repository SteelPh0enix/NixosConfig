"""HTML metadata extraction helpers."""

from bs4 import BeautifulSoup, Tag


def extract_page_metadata(html_bytes: bytes) -> dict:
    """Extract title, description, og:* tags from raw HTML bytes."""
    result: dict = {}
    try:
        soup = BeautifulSoup(html_bytes[:32768], "html.parser")

        title_tag = soup.find("title")
        if title_tag:
            result["title"] = title_tag.get_text(strip=True)

        for prop in ["og:title", "og:description", "og:site_name", "og:locale"]:
            tag = soup.find("meta", property=prop)
            if tag and isinstance(tag, Tag):
                v = tag.get("content")
                if v:
                    result[prop.split(":")[-1]] = str(v).strip()

        for name in ["description", "author", "date"]:
            tag = soup.find("meta", attrs={"name": name})
            if tag and isinstance(tag, Tag):
                v = tag.get("content")
                if v and name not in result:
                    result[name] = str(v).strip()

    except Exception:
        return result
    return result
