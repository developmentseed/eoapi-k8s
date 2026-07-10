"""Integration test for the STAC Browser bare-path redirect on Traefik.

The browser image bakes in a ``pathPrefix``, so it only answers on the
trailing-slash form and the bare path used to 404. The chart adds a Traefik
``redirectRegex`` middleware so ``GET /browser`` 301-redirects to ``/browser/``.
See PR #544 / issue #545.
"""

import os

import httpx

# Same client setup as the other integration modules, but keep redirects
# unfollowed so we can assert on the 301 itself.
timeout = httpx.Timeout(15.0, connect=60.0)
if bool(os.getenv("IGNORE_SSL_VERIFICATION", False)):
    client = httpx.Client(timeout=timeout, verify=False, follow_redirects=False)
else:
    client = httpx.Client(timeout=timeout, follow_redirects=False)


def test_browser_bare_path_redirects_to_slash(browser_endpoint: str) -> None:
    """GET /browser 301-redirects to /browser/ (Traefik redirect middleware).

    The redirect is handled by Traefik, so it holds even before the browser
    pod is ready.
    """
    resp = client.get(browser_endpoint)
    assert resp.status_code == 301
    assert resp.headers["location"] == f"{browser_endpoint}/"


def test_browser_trailing_slash_serves(browser_endpoint: str) -> None:
    """The trailing-slash form serves the STAC Browser app (HTTP 200)."""
    resp = client.get(f"{browser_endpoint}/")
    assert resp.status_code == 200
