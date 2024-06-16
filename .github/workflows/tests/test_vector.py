"""test EOapi.vector"""

import httpx

vector_endpoint="http://k8s-gcorradi-nginxing-553d3ea33b-3eef2e6e61e5d161.elb.us-west-1.amazonaws.com/vector/"


def test_vector_api():
    """test vector."""
    # better timeouts
    timeout = httpx.Timeout(15.0, connect=60.0)
    client = httpx.Client(timeout=timeout)

    # landing
    resp = client.get(f"{vector_endpoint}/")
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "application/json"
    assert resp.json()["links"]

    # conformance
    resp = client.get(f"{vector_endpoint}/conformance")
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "application/json"
    assert resp.json()["conformsTo"]

    # refresh to get newest catalog
    resp = client.get(f"{vector_endpoint}/refresh")
    assert resp.status_code == 200

    # collections
    resp = client.get(f"{vector_endpoint}/collections")
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "application/json"

    assert list(resp.json()) == [
        "links",
        "numberMatched",
        "numberReturned",
        "collections",
    ]
    assert resp.json()["numberMatched"] == 7  # one public table + 5 functions
    assert resp.json()["numberReturned"] == 7

    collections = resp.json()["collections"]
    ids = [c["id"] for c in collections]
    # 3 Functions
    assert "public.st_squaregrid" in ids
    assert "public.st_hexagongrid" in ids
    assert "public.st_subdivide" in ids
    # 1 public table
    assert "public.my_data" in ids

    # collection
    resp = client.get(f"{vector_endpoint}/collections/public.my_data")
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "application/json"
    assert resp.json()["links"]
    assert resp.json()["itemType"] == "feature"

    # items
    resp = client.get(
        f"{vector_endpoint}/collections/public.my_data/items"
    )
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "application/geo+json"
    items = resp.json()["features"]
    assert len(items) == 6

    # limit
    resp = client.get(
        f"{vector_endpoint}/collections/public.my_data/items",
        params={"limit": 1},
    )
    assert resp.status_code == 200
    items = resp.json()["features"]
    assert len(items) == 1

    # intersects
    resp = client.get(
        f"{vector_endpoint}/collections/public.my_data/items",
        params={"bbox": "-180,0,0,90"},
    )
    assert resp.status_code == 200
    items = resp.json()["features"]
    assert len(items) == 6

    # item
    resp = client.get(
        f"{vector_endpoint}/collections/public.my_data/items/1"
    )
    assert resp.status_code == 200
    item = resp.json()
    assert item["id"] == 1

    # OGC Tiles
    resp = client.get(f"{vector_endpoint}/collections/public.my_data/tiles/0/0/0")
    assert resp.status_code == 200

    resp = client.get(
        f"{vector_endpoint}/collections/public.my_data/tilejson.json"
    )
    assert resp.status_code == 200

    resp = client.get(f"{vector_endpoint}/tileMatrixSets")
    assert resp.status_code == 200

    resp = client.get(f"{vector_endpoint}/tileMatrixSets/WebMercatorQuad")
    assert resp.status_code == 200
