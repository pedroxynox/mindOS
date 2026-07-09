"""Per-user LLM cost accounting (design §7.1, first-class metric #02).

Persists the usage/cost of every model call into ``llm_usage``, attributed to
the job's user. It is called **inside** the RLS transaction of the write step,
so a cost row is isolated per user exactly like the rest of that user's data
(the ``llm_usage`` RLS policy from the F2 migration enforces it).
"""

from typing import Any

from app.providers.base import Usage


class CostMeter:
    """Writes ``llm_usage`` rows on the caller's (already RLS-scoped) connection."""

    async def record(
        self, conn: Any, user_id: str, capture_id: str, usage: Usage
    ) -> None:
        """Record a single model call's usage/cost."""
        await conn.execute(
            """
            INSERT INTO llm_usage
                (user_id, capture_id, provider, model, operation,
                 input_tokens, output_tokens, cost_usd)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            """,
            user_id,
            capture_id,
            usage.provider,
            usage.model,
            usage.operation,
            usage.input_tokens,
            usage.output_tokens,
            usage.cost_usd,
        )

    async def record_all(
        self, conn: Any, user_id: str, capture_id: str, usages: list[Usage]
    ) -> None:
        """Record every model call made for one capture."""
        for usage in usages:
            await self.record(conn, user_id, capture_id, usage)
