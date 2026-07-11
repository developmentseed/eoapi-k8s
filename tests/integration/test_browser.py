"""Integration test for the STAC Browser bare-path redirect.

The browser image bakes in a ``pathPrefix``, so it only answers on the
trailing-slash form and the bare path used to 404. The chart redirects
``GET /browser`` to ``/browser/`` on both NGINX and Traefik.
See PR #544 / issue #545.
"""

import os
from urllib.parse import urlparse

import httpx

# Same client setup as the other integration modules, but keep redirects
# unfollowed so we can assert on the 301 itself.
timeout = httpx.Timeout(15.0, connect=60.0)
if bool(os.getenv("IGNORE_SSL_VERIFICATION", False)):
    client = httpx.Client(timeout=timeout, verify=False, follow_redirects=False)
else:
    client = httpx.Client(timeout=timeout, follow_redirects=False)


def test_browser_bare_path_redirects_to_slash(browser_endpoint: str) -> None:
    """GET /browser redirects to /browser/ (ingress redirect rule).

    NGINX returns 301; Traefik returns 308. The redirect is handled at ingress,
    so it holds even before the browser pod is ready.
    """
    resp = client.get(browser_endpoint)
    assert resp.status_code in (301, 308)
    location = urlparse(resp.headers["location"])
    endpoint = urlparse(browser_endpoint)
    assert location.path == endpoint.path.rstrip("/") + "/"


def test_browser_trailing_slash_serves(browser_endpoint: str) -> None:
    """The trailing-slash form serves the STAC Browser app (HTTP 200)."""
    resp = client.get(f"{browser_endpoint}/")
    assert resp.status_code == 200
