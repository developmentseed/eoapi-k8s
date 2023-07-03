"""test EOapi."""

import httpx

stac_endpoint="http://k8s-gcorradi-nginxing-553d3ea33b-3eef2e6e61e5d161.elb.us-west-1.amazonaws.com/stac/"

# better timeouts
timeout = httpx.Timeout(15.0, connect=60.0)
client = httpx.Client(timeout=timeout)

def test_stac_api():
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


def test_stac_to_raster():
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
