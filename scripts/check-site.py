#!/usr/bin/env python3
"""Validate the buildless Pages payload, including project-subpath navigation."""

from html.parser import HTMLParser
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent / "site"
errors = []


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.path = path
        self.ids = set()
        self.links = []
        self.headings = 0
        self.has_lang = False
        self.has_csp = False
        self.has_title = False
        self.language = None
        self.alternate = None

    def handle_starttag(self, tag, pairs):
        attrs = dict(pairs)
        if tag == "html":
            self.has_lang = bool(attrs.get("lang"))
            self.language = attrs.get("lang")
        if tag == "link" and attrs.get("rel") == "alternate":
            self.alternate = (attrs.get("hreflang"), attrs.get("href"))
        if tag == "h1":
            self.headings += 1
        if tag == "title":
            self.has_title = True
        if tag == "meta" and attrs.get("http-equiv", "").lower() == "content-security-policy":
            self.has_csp = "default-src 'none'" in attrs.get("content", "")
        if tag == "img" and "alt" not in attrs:
            errors.append(f"{self.path.name}: image without alt")
        if tag in {"iframe", "object", "embed", "form", "base"}:
            errors.append(f"{self.path.name}: unsupported element {tag}")
        if tag == "script" and not attrs.get("src"):
            errors.append(f"{self.path.name}: inline script")
        if any(key.startswith("on") or key == "style" for key in attrs):
            errors.append(f"{self.path.name}: inline code/style")
        if "id" in attrs:
            if attrs["id"] in self.ids:
                errors.append(f"{self.path.name}: duplicate id {attrs['id']}")
            self.ids.add(attrs["id"])
        for attr in ("href", "src"):
            if attr in attrs:
                self.links.append((attrs[attr], attr))


pages = {}
for path in sorted(ROOT.rglob("*.html")):
    page = Page(path)
    page.feed(path.read_text(encoding="utf-8"))
    pages[path.resolve()] = page
    if not all((page.has_lang, page.has_csp, page.has_title, page.headings == 1)):
        errors.append(f"{path.name}: missing language/CSP/title or incorrect h1 count")
    english = path.parent.name == "en"
    expected_language = "en" if english else "zh-CN"
    counterpart = ROOT / ("" if english else "en") / path.name
    if page.language != expected_language or not counterpart.is_file():
        errors.append(f"{path.relative_to(ROOT)}: missing or incorrect language counterpart")
    if not page.alternate or page.alternate[0] != ("zh-CN" if english else "en"):
        errors.append(f"{path.relative_to(ROOT)}: missing alternate-language link")

for path, page in pages.items():
    for value, attr in page.links:
        url = urlsplit(value)
        if url.scheme:
            if url.scheme != "https" or not url.netloc or attr == "src":
                errors.append(f"{path.name}: unsupported external resource {value}")
            continue
        if url.netloc:
            errors.append(f"{path.name}: protocol-relative link")
            continue
        relative = unquote(url.path)
        if relative.startswith("/mac-island/"):
            target = (ROOT / relative.removeprefix("/mac-island/")).resolve()
        elif relative.startswith("/"):
            errors.append(f"{path.name}: link misses project prefix {value}")
            continue
        else:
            target = (path.parent / relative).resolve() if relative else path
        if target != ROOT.resolve() and ROOT.resolve() not in target.parents:
            errors.append(f"{path.name}: link escapes published directory")
        elif not target.is_file():
            errors.append(f"{path.name}: missing local link {value}")
        elif url.fragment and target in pages and unquote(url.fragment) not in pages[target].ids:
            errors.append(f"{path.name}: missing anchor {value}")

allowed = {".html", ".css", ".js", ".png"}
for path in ROOT.rglob("*"):
    if path.is_symlink() or (path.is_file() and path.suffix not in allowed and path.name != ".nojekyll"):
        errors.append(f"Unexpected Pages payload: {path.relative_to(ROOT)}")
expected_pages = {f"{prefix}{name}.html" for prefix in ("", "en/")
                  for name in ("index", "guide", "privacy", "support", "licenses", "404")}
if {str(path.relative_to(ROOT)) for path in pages} != expected_pages:
    errors.append("Expected exactly six corresponding Chinese and English pages")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"Pages payload OK: {len(pages)} pages, local links/anchors, self-hosted resources and structural checks")
