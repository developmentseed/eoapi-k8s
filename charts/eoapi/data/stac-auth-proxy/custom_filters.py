import dataclasses

from typing import Any


@dataclasses.dataclass
class CollectionsFilter:
    async def __call__(self, context: dict[str, Any]) -> str:
        return "1=1"


@dataclasses.dataclass
class ItemsFilter:
    async def __call__(self, context: dict[str, Any]) -> str:
        return "1=1"
