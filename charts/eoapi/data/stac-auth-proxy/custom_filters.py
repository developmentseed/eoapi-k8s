"""
Sample custom filters for STAC Auth Proxy.
This file demonstrates the structure needed for custom collection and item filters.
"""

import dataclasses
from typing import Any


@dataclasses.dataclass
class CollectionsFilter:
    """Returns CQL2 filter for /collections endpoint."""

    async def __call__(self, context: dict[str, Any]) -> str | dict[str, Any]:
        """
        Return format:
        - CQL2-text string: "1=1" or "private = false"
        - CQL2-JSON dict: {"op": "=", "args": [{"property": "owner"}, "user123"]}

        Examples:
        - Allow all: return "1=1"
        - User-specific: return f"owner = '{context['token']['sub']}'"
        - Public only: return "private = false" if not context["token"] else "1=1"
        - Complex: return {"op": "in", "args": [{"property": "id"}, ["col1", "col2"]]}
        """
        return "1=1"


@dataclasses.dataclass
class ItemsFilter:
    """Returns CQL2 filter for /search and /collections/{id}/items endpoints."""

    async def __call__(self, context: dict[str, Any]) -> str | dict[str, Any]:
        """
        Examples:
        - Allow all: return "1=1"
        - Collection-based: return f"collection = '{context['collection_id']}'"
        - User-specific: return f"properties.owner = '{context['token']['sub']}'"
        - Complex: return {"op": "in", "args": [{"property": "collection"}, approved_list]}
        """
        return "1=1"
