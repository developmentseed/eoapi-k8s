"""Integration test for the STAC Browser bare-path handling."""

import os

import httpx

timeout = httpx.Timeout(15.0, connect=60.0)
if bool(os.getenv("IGNORE_SSL_VERIFICATION", False)):
    client = httpx.Client(timeout=timeout, verify=False, follow_redirects=True)
else:
    client = httpx.Client(timeout=timeout, follow_redirects=True)


def test_browser_bare_path_serves(browser_endpoint: str) -> None:
    resp = client.get(browser_endpoint)
    assert resp.status_code == 200


def test_browser_trailing_slash_serves(browser_endpoint: str) -> None:
    resp = client.get(f"{browser_endpoint}/")
    assert resp.status_code == 200
