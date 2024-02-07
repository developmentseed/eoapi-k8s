"""Create STAC Collections and Items files."""

import json
import logging
import sys
import time

import pystac


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def generate_items(collection_id):
    """Create STAC items file for a given collection."""
    # catalog_path = "https://maxar-opendata.s3.amazonaws.com/events/catalog.json"
    catalog_path = "/catalog.json"
    catalog = pystac.Catalog.from_file(catalog_path)
    tries = 1
    while tries <= 3:
        try:
            collections = list(catalog.get_collections())
            break
        except Exception as e:
            logger.exception(f"Error getting collections from catalog")
            time.sleep(tries * 2)
        
    found_collection = False
    errors = []

    for collection in collections:
        if collection.id == collection_id:
            found_collection = True
            logger.info(f"Processing items for {collection_id}")
            collection_id = "MAXAR_" + collection.id.replace("-","_")
            items_file = f"/data/{collection_id}_items.json"
            with open(items_file, "w") as f:
                count = 0
                # Each Collection has collections
                try:
                    child_collections = collection.get_collections()
                except Exception as e:
                    logger.exception(f"Error getting child collections for {collection_id}")
                    errors.append(e)
                    continue
                for c in child_collections:
                    # Loop through each items
                    # edit items and save into a top level collection JSON file
                    try:
                        items = c.get_all_items()
                    except Exception as e:
                        logger.exception(f"Error getting items for {c.id}")
                        errors.append(e)
                        continue
                    for item in items:
                        item_dict = item.make_asset_hrefs_absolute().to_dict()
                        item_dict["links"] = []
                        item_dict["collection"] = collection_id
                        item_dict["id"] = item.id.replace("/", "_")
                        item_str = json.dumps(item_dict)
                        f.write(item_str + "\n")
                        count += 1
                        # TODO: Remove this break. Keeping it short for test runs
                        if count > 100:
                            break
                    logger.info(f"Processed {count} items into {items_file}")
                    #TODO: Remove this break. Keeping it short for test runs
                    break
            break
    if not found_collection:
        logger.info(f"Collection {collection_id} not found")
    if errors:
        logger.info(f"{len(errors)} errors occurred while processing {collection_id}")


if __name__ == "__main__":
    collection_id = sys.argv[1]
    generate_items(collection_id)