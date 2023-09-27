"""Create STAC Collections and Items files."""

import json
import logging
import sys

import pystac

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def process_catalog():
    # catalog_path = "https://maxar-opendata.s3.amazonaws.com/events/catalog.json"
    catalog_path = "/catalog.json"
    catalog = pystac.Catalog.from_file(catalog_path)
    try:
        collections = list(catalog.get_collections())
    except Exception as e:
        logger.exception(f"Error getting collections from catalog")
        sys.exit(1)
    logger.info(f"Found {len(collections)} collections")
    logger.info(collections)

    logger.info("Creating collections.json file...")
    with open("/data/collections.json", "w") as f:
        for collection in collections:
            c = collection.to_dict()
            c["links"] = []
            c["id"] = "MAXAR_" + c["id"].replace("-","_")
            c["description"] = "Maxar OpenData | " + c["description"]
            f.write(json.dumps(c) + "\n")


    item_file_set = set()
    collection_id_set = set()
    for collection in collections:
        collection_id_set.add(collection.id)
        collection_id = "MAXAR_" + collection.id.replace("-","_")
        items_file = f"/data/{collection_id}_items.json"
        item_file_set.add(items_file)

    with open("/data/collection-ids.json", "w") as fp:
        json.dump(list(collection_id_set), fp)

    with open("/data/items-paths.json", "w") as fp:
        json.dump(list(item_file_set), fp)

if __name__ == "__main__":
    process_catalog()