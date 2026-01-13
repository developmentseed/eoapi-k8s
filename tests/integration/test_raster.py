"""test EOapi."""

import os

import httpx

# better timeouts
timeout = httpx.Timeout(15.0, connect=60.0)
if bool(os.getenv("IGNORE_SSL_VERIFICATION", False)):
    client = httpx.Client(timeout=timeout, verify=False)
else:
    client = httpx.Client(timeout=timeout)


def test_raster_api(raster_endpoint: str) -> None:
    """test api."""
    resp = client.get(
        f"{raster_endpoint}/healthz", headers={"Accept-Encoding": "br, gzip"}
    )
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "application/json"


def test_mosaic_api(raster_endpoint: str) -> None:
    """test mosaic."""
    query = {
        "collections": ["noaa-emergency-response"],
        "filter-lang": "cql2-json",
    }
    resp = client.post(f"{raster_endpoint}/searches/register", json=query)
    assert resp.headers["content-type"] == "application/json"
    assert resp.status_code == 200
    assert resp.json()["id"]
    assert resp.json()["links"]

    searchid = resp.json()["id"]

    resp = client.get(
        f"{raster_endpoint}/searches/{searchid}/point/-85.6358,36.1624/assets"
    )
    assert resp.status_code == 200
    assert len(resp.json()) == 1
    assert list(resp.json()[0]) == ["id", "bbox", "assets", "collection"]
    assert resp.json()[0]["id"] == "20200307aC0853900w361030"

    resp = client.get(
        f"{raster_endpoint}/searches/{searchid}/tiles/WebMercatorQuad/15/8589/12849/assets"
    )
    assert resp.status_code == 200
    assert len(resp.json()) == 1
    assert list(resp.json()[0]) == ["id", "bbox", "assets", "collection"]
    assert resp.json()[0]["id"] == "20200307aC0853900w361030"

    z, x, y = 15, 8589, 12849
    resp = client.get(
        f"{raster_endpoint}/searches/{searchid}/tiles/WebMercatorQuad/{z}/{x}/{y}",
        params={"assets": "cog"},
        headers={"Accept-Encoding": "br, gzip"},
        timeout=10.0,
    )
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "image/jpeg"
    assert "content-encoding" not in resp.headers


def test_mosaic_collection_api(raster_endpoint: str) -> None:
    """test mosaic collection."""
    resp = client.get(
        f"{raster_endpoint}/collections/noaa-emergency-response/point/-85.6358,36.1624/assets"
    )
    assert resp.status_code == 200
    assert len(resp.json()) == 1
    assert list(resp.json()[0]) == ["id", "bbox", "assets", "collection"]
    assert resp.json()[0]["id"] == "20200307aC0853900w361030"

    resp = client.get(
        f"{raster_endpoint}/collections/noaa-emergency-response/tiles/WebMercatorQuad/15/8589/12849/assets"
    )
    assert resp.status_code == 200
    assert len(resp.json()) == 1
    assert list(resp.json()[0]) == ["id", "bbox", "assets", "collection"]
    assert resp.json()[0]["id"] == "20200307aC0853900w361030"

    z, x, y = 15, 8589, 12849
    resp = client.get(
        f"{raster_endpoint}/collections/noaa-emergency-response/tiles/WebMercatorQuad/{z}/{x}/{y}",
        params={"assets": "cog"},
        headers={"Accept-Encoding": "br, gzip"},
        timeout=10.0,
    )
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "image/jpeg"
    assert "content-encoding" not in resp.headers


def test_mosaic_search(raster_endpoint: str) -> None:
    """test mosaic."""
    # register some fake mosaic
    searches = [
        {
            "filter": {
                "op": "=",
                "args": [{"property": "collection"}, "collection1"],
            },
            "metadata": {"owner": "vincent"},
        },
        {
            "filter": {
                "op": "=",
                "args": [{"property": "collection"}, "collection2"],
            },
            "metadata": {"owner": "vincent"},
        },
        {
            "filter": {
                "op": "=",
                "args": [{"property": "collection"}, "collection3"],
            },
            "metadata": {"owner": "vincent"},
        },
        {
            "filter": {
                "op": "=",
                "args": [{"property": "collection"}, "collection4"],
            },
            "metadata": {"owner": "vincent"},
        },
        {
            "filter": {
                "op": "=",
                "args": [{"property": "collection"}, "collection5"],
            },
            "metadata": {"owner": "vincent"},
        },
        {
            "filter": {
                "op": "=",
                "args": [{"property": "collection"}, "collection6"],
            },
            "metadata": {"owner": "vincent"},
        },
        {
            "filter": {
                "op": "=",
                "args": [{"property": "collection"}, "collection7"],
            },
            "metadata": {"owner": "vincent"},
        },
        {
            "filter": {
                "op": "=",
                "args": [{"property": "collection"}, "collection8"],
            },
            "metadata": {"owner": "sean"},
        },
        {
            "filter": {
                "op": "=",
                "args": [{"property": "collection"}, "collection9"],
            },
            "metadata": {"owner": "sean"},
        },
        {
            "filter": {
                "op": "=",
                "args": [{"property": "collection"}, "collection10"],
            },
            "metadata": {"owner": "drew"},
        },
        {
            "filter": {
                "op": "=",
                "args": [{"property": "collection"}, "collection11"],
            },
            "metadata": {"owner": "drew"},
        },
        {
            "filter": {
                "op": "=",
                "args": [{"property": "collection"}, "collection12"],
            },
            "metadata": {"owner": "drew"},
        },
    ]
    for search in searches:
        resp = client.post(f"{raster_endpoint}/searches/register", json=search)
        assert resp.status_code == 200
        assert resp.json()["id"]

    resp = client.get(f"{raster_endpoint}/searches/list")
    assert resp.headers["content-type"] == "application/json"
    assert resp.status_code == 200
    assert (
        resp.json()["context"]["matched"] > 10
    )  # there should be at least 12 mosaic registered
    assert resp.json()["context"]["returned"] == 10  # default limit is 10

    # Make sure all mosaics returned have
    for mosaic in resp.json()["searches"]:
        assert mosaic["search"]["metadata"]["type"] == "mosaic"

    links = resp.json()["links"]
    assert len(links) == 2
    assert links[0]["rel"] == "self"
    assert links[1]["rel"] == "next"
    assert links[1]["href"] == f"{raster_endpoint}/searches/list?limit=10&offset=10"

    resp = client.get(
        f"{raster_endpoint}/searches/list", params={"limit": 1, "offset": 1}
    )
    assert resp.status_code == 200
    assert resp.json()["context"]["matched"] > 10
    assert resp.json()["context"]["limit"] == 1
    assert resp.json()["context"]["returned"] == 1

    links = resp.json()["links"]
    assert len(links) == 3
    assert links[0]["rel"] == "self"
    assert links[0]["href"] == f"{raster_endpoint}/searches/list?limit=1&offset=1"
    assert links[1]["rel"] == "next"
    assert links[1]["href"] == f"{raster_endpoint}/searches/list?limit=1&offset=2"
    assert links[2]["rel"] == "prev"
    assert links[2]["href"] == f"{raster_endpoint}/searches/list?limit=1&offset=0"

    # Filter on mosaic metadata
    resp = client.get(f"{raster_endpoint}/searches/list", params={"owner": "vincent"})
    assert resp.status_code == 200
    assert resp.json()["context"]["matched"] == 7
    assert resp.json()["context"]["limit"] == 10
    assert resp.json()["context"]["returned"] == 7

    # sortBy
    resp = client.get(f"{raster_endpoint}/searches/list", params={"sortby": "lastused"})
    assert resp.status_code == 200

    resp = client.get(f"{raster_endpoint}/searches/list", params={"sortby": "usecount"})
    assert resp.status_code == 200

    resp = client.get(f"{raster_endpoint}/searches/list", params={"sortby": "-owner"})
    assert resp.status_code == 200
    assert (
        "owner" not in resp.json()["searches"][0]["search"]["metadata"]
    )  # some mosaic don't have owners

    resp = client.get(f"{raster_endpoint}/searches/list", params={"sortby": "owner"})
    assert resp.status_code == 200
    assert "owner" in resp.json()["searches"][0]["search"]["metadata"]


def test_item(raster_endpoint: str) -> None:
    """test stac endpoints."""
    resp = client.get(
        f"{raster_endpoint}/collections/noaa-emergency-response/items/20200307aC0853300w361200/assets",
    )
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "application/json"
    assert resp.json() == ["cog"]

    resp = client.get(
        f"{raster_endpoint}/collections/noaa-emergency-response/items/20200307aC0853300w361200/WebMercatorQuad/tilejson.json",
        params={
            "assets": "cog",
        },
    )
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "application/json"
    assert resp.json()["tilejson"]
    assert "assets=cog" in resp.json()["tiles"][0]
    assert (
        "/collections/noaa-emergency-response/items/20200307aC0853300w361200"
        in resp.json()["tiles"][0]
    )
    assert resp.json()["bounds"] == [-85.5501, 36.1749, -85.5249, 36.2001]
