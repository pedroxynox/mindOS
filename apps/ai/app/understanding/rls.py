"""RLS transaction context for the Python worker (design §8.4).

Mirrors F1's fail-closed pattern: open a transaction and set
``app.current_user_id`` **local to that transaction** (``set_config(..., true)``)
so a pooled connection never leaks one user's context into the next request. The
worker connects as the non-owner ``mindos_app`` role, so ``FORCE ROW LEVEL
SECURITY`` (F1 §6) always applies — even a query that forgot to filter by user
cannot read or write another user's rows.

``asyncpg`` is imported lazily so the offline test suite (which uses
``InMemoryGraphStore``) does not need the driver installed.
"""

from contextlib import asynccontextmanager
from typing import TYPE_CHECKING, Any, AsyncIterator

if TYPE_CHECKING:  # pragma: no cover - typing only
    import asyncpg


async def create_pool(dsn: str, *, min_size: int = 1, max_size: int = 10) -> Any:
    """Create an asyncpg pool. Lazy import keeps the driver an optional dep."""
    import asyncpg

    return await asyncpg.create_pool(dsn, min_size=min_size, max_size=max_size)


@asynccontextmanager
async def rls_tx(pool: Any, user_id: str) -> "AsyncIterator[asyncpg.Connection]":
    """Yield a connection inside a transaction with the RLS context set.

    ``set_config(..., true)`` scopes ``app.current_user_id`` to this transaction
    only; on commit/rollback it is discarded, so the connection returns to the
    pool with no residual identity (fail-closed).
    """
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "SELECT set_config('app.current_user_id', $1, true)", user_id
            )
            yield conn
