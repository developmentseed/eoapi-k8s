"""test EOapi."""
import httpx
import os

timeout = httpx.Timeout(15.0, connect=60.0)
if bool(os.getenv("IGNORE_SSL_VERIFICATION", False)):
    client = httpx.Client(timeout=timeout, verify=False)
else:
    client = httpx.Client(timeout=timeout)


def test_stac_api(stac_endpoint):
    """test stac."""
    # Ping
    assert client.get(f"{stac_endpoint}/_mgmt/ping").status_code == 200

    # Landing page
    resp = client.get(stac_endpoint)
    assert resp.status_code == 200
    landing = resp.json()
    # Verify landing page links have correct base path
    for link in landing["links"]:
        if link["href"].startswith("/"):
            assert link["href"].startswith(stac_endpoint.split("://")[1])

    # viewer
    #assert client.get(f"{stac_endpoint}/index.html").status_code == 200
    assert client.get(f"{stac_endpoint}/index.html").status_code == 404

    # Collections
    resp = client.get(f"{stac_endpoint}/collections")
    assert resp.status_code == 200
    collections = resp.json()["collections"]
    assert len(collections) > 0
    ids = [c["id"] for c in collections]
    assert "noaa-emergency-response" in ids

    # Verify collection links have correct base path
    for collection in collections:
        for link in collection["links"]:
            if link["href"].startswith("/"):
                assert link["href"].startswith(stac_endpoint.split("://")[1])

    # items
    resp = client.get(f"{stac_endpoint}/collections/noaa-emergency-response/items")
    assert resp.status_code == 200
    items = resp.json()
    # Verify item links have correct base path
    for feature in items["features"]:
        for link in feature["links"]:
            if link["href"].startswith("/"):
                assert link["href"].startswith(stac_endpoint.split("://")[1])

    # item
    resp = client.get(
        f"{stac_endpoint}/collections/noaa-emergency-response/items/20200307aC0853300w361200"
    )
    assert resp.status_code == 200
    item = resp.json()
    assert item["id"] == "20200307aC0853300w361200"


def test_stac_to_raster(stac_endpoint):
    """test link to raster api."""
    # tilejson
    resp = client.get(
        f"{stac_endpoint}/collections/noaa-emergency-response/items/20200307aC0853300w361200/tilejson.json",
        params={"assets": "cog"},
    )
    #assert resp.status_code == 307
    assert resp.status_code == 404

def test_stac_custom_path(stac_endpoint):
    """test stac with custom ingress path."""
    # If we're using a custom path (e.g., /api instead of /stac)
    base_path = stac_endpoint.split("://")[1]

    # Landing page
    resp = client.get(stac_endpoint)
    assert resp.status_code == 200
    landing = resp.json()

    # All links should use the custom path
    for link in landing["links"]:
        if link["href"].startswith("/"):
            assert link["href"].startswith(base_path), \
                f"Link {link['href']} doesn't start with {base_path}"

    # Collections should also use the custom path
    resp = client.get(f"{stac_endpoint}/collections")
    assert resp.status_code == 200
    collections = resp.json()["collections"]

    for collection in collections:
        for link in collection["links"]:
            if link["href"].startswith("/"):
                assert link["href"].startswith(base_path), \
                    f"Collection link {link['href']} doesn't start with {base_path}"

    # Test a specific item
    resp = client.get(f"{stac_endpoint}/collections/noaa-emergency-response/items")
    assert resp.status_code == 200
    items = resp.json()

    # Item links should also use the custom path
    for feature in items["features"]:
        for link in feature["links"]:
            if link["href"].startswith("/"):
                assert link["href"].startswith(base_path), \
                    f"Item link {link['href']} doesn't start with {base_path}"

    # viewer
    resp = client.get(
        f"{stac_endpoint}/collections/noaa-emergency-response/items/20200307aC0853300w361200/viewer",
        params={"assets": "cog"},
    )
    #assert resp.status_code == 307
    assert resp.status_code == 404
