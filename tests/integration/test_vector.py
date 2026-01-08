import os
import time

import httpx

timeout = httpx.Timeout(15.0, connect=60.0)
if bool(os.getenv("IGNORE_SSL_VERIFICATION", False)):
    client = httpx.Client(timeout=timeout, verify=False)
else:
    client = httpx.Client(timeout=timeout)


def test_vector_api(vector_endpoint: str) -> None:
    """test vector."""
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

    total_timeout = 60 * 2
    start_time = time.time()
    while True:
        collections_data = resp.json()
        current_count = collections_data.get("numberMatched", 0)
        print(f"Current collections count: {current_count}/7")

        if current_count == 7:
            break

        elapsed_time = time.time() - start_time
        if elapsed_time > total_timeout:
            print(
                f"Timeout exceeded after {elapsed_time:.1f}s. Expected 7 collections, got {current_count}"
            )
            if "collections" in collections_data:
                available_collections = [
                    c.get("id", "unknown") for c in collections_data["collections"]
                ]
                print(f"Available collections: {available_collections}")
            assert False, f"Expected 7 collections but found {current_count} after {elapsed_time:.1f}s timeout"

        time.sleep(10)
        resp = client.get(f"{vector_endpoint}/collections")

    collections_data = resp.json()
    matched_count = collections_data.get("numberMatched", 0)
    returned_count = collections_data.get("numberReturned", 0)

    assert matched_count == 7, (
        f"Expected 7 matched collections, got {matched_count}. "
        f"Available: {[c.get('id', 'unknown') for c in collections_data.get('collections', [])]}"
    )
    assert returned_count == 7, f"Expected 7 returned collections, got {returned_count}"

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
    resp = client.get(f"{vector_endpoint}/collections/public.my_data/items")
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
    resp = client.get(f"{vector_endpoint}/collections/public.my_data/items/1")
    assert resp.status_code == 200
    item = resp.json()
    assert item["id"] == 1

    # OGC Tiles
    resp = client.get(
        f"{vector_endpoint}/collections/public.my_data/tiles/WebMercatorQuad/0/0/0"
    )
    assert resp.status_code == 200

    resp = client.get(
        f"{vector_endpoint}/collections/public.my_data/tiles/WebMercatorQuad/tilejson.json"
    )
    assert resp.status_code == 200

    resp = client.get(f"{vector_endpoint}/tileMatrixSets")
    assert resp.status_code == 200

    resp = client.get(f"{vector_endpoint}/tileMatrixSets/WebMercatorQuad")
    assert resp.status_code == 200
