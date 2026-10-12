"""Reads the frontend production build over HTTP for the security tests.

Starts from the app's index.html (APP_URL, served by vite preview), follows
every script, stylesheet, icon and preload it references, and then every
further JavaScript or CSS file those files refer to (Vite splits the app into
chunks). Used to check that every asset loads under the deployment sub-path
and that no secret has been built into the code sent to browsers.
"""

import re
from urllib.parse import urljoin, urlparse

import requests
from robot.api.deco import keyword, library

# Attributes in index.html that point to files the browser loads
HTML_REFERENCE = re.compile(r'<(?:script|link|img)\b[^>]*?\b(?:src|href)="([^"]+)"', re.IGNORECASE)
# Paths to other built files mentioned inside JavaScript or CSS: relative to
# the file itself ("./chunk.js"), absolute ("/base/assets/chunk.js") or
# relative to the base path ("assets/chunk.js", used by Vite's preloader)
RELATIVE_TO_FILE = re.compile(r'["\'(](\.{1,2}/[\w./-]+\.(?:js|css))["\')]')
ABSOLUTE_ASSET = re.compile(r'["\'(](/[\w./-]*/assets/[\w.-]+\.(?:js|css))["\')]')
RELATIVE_TO_BASE = re.compile(r'["\'(](assets/[\w.-]+\.(?:js|css))["\')]')

# Things that must never be in code sent to the browser
SECRET_PATTERNS = {
    "OpenAI API key": re.compile(r"sk-(?:proj-)?[A-Za-z0-9_-]{20,}"),
    "Clerk secret key": re.compile(r"sk_(?:test|live)_[A-Za-z0-9]{10,}"),
    "Clerk webhook signing secret": re.compile(r"whsec_[A-Za-z0-9+/=]{10,}"),
    "MongoDB connection string": re.compile(r"mongodb(?:\+srv)?://[^\s\"'`]+"),
    "Backend secret variable name": re.compile(r"\b(?:OPENAI_API_KEY|MONGODB_URI)\b"),
}


@library(scope="GLOBAL")
class FrontendBuild:
    @keyword
    def crawl_frontend_build(self, app_url):
        """Returns every file of the build reachable from index.html.

        Each item is a dictionary with ``url``, ``status``, ``text`` and
        ``found_in`` (the file that referred to it). Files on other origins
        (for example Clerk's script) are listed with status ``None`` and are
        not downloaded.
        """
        origin = "{0.scheme}://{0.netloc}".format(urlparse(app_url))
        files = []
        seen = set()
        queue = [(app_url, "start")]
        while queue:
            url, found_in = queue.pop(0)
            if url in seen:
                continue
            seen.add(url)
            if not url.startswith(origin):
                files.append({"url": url, "status": None, "text": "", "found_in": found_in})
                continue
            response = requests.get(url, timeout=30)
            text = response.text if response.ok else ""
            files.append({"url": url, "status": response.status_code, "text": text, "found_in": found_in})
            if not response.ok:
                continue
            if url == app_url:
                targets = [urljoin(app_url, ref) for ref in HTML_REFERENCE.findall(text)]
            elif url.endswith((".js", ".css")):
                targets = (
                    [urljoin(url, ref) for ref in RELATIVE_TO_FILE.findall(text)]
                    + [urljoin(origin, ref) for ref in ABSOLUTE_ASSET.findall(text)]
                    + [urljoin(app_url, ref) for ref in RELATIVE_TO_BASE.findall(text)]
                )
            else:
                targets = []
            for target in targets:
                if not target.startswith(("data:", "blob:")):
                    queue.append((target, url))
        return files

    @keyword
    def find_secrets(self, files):
        """Returns a list of "<what> in <url>" for every secret pattern found."""
        findings = []
        for item in files:
            for name, pattern in SECRET_PATTERNS.items():
                if pattern.search(item["text"]):
                    findings.append(f"{name} in {item['url']}")
        return findings