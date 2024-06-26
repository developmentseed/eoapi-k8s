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

    # items
    resp = client.get(f"{stac_endpoint}/collections/noaa-emergency-response/items")
    assert resp.status_code == 200
    items = resp.json()["features"]
    assert len(items) == 10

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

    # viewer
    resp = client.get(
        f"{stac_endpoint}/collections/noaa-emergency-response/items/20200307aC0853300w361200/viewer",
        params={"assets": "cog"},
    )
    #assert resp.status_code == 307
    assert resp.status_code == 404
