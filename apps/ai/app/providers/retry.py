"""Async retry with exponential backoff + jitter for transient API failures.

Provider-agnostic: the caller decides *which* exceptions are retryable and how
to read any server-provided ``Retry-After`` hint. This keeps the OpenAI SDK
imports isolated to :mod:`app.providers.openai_provider` and makes the retry
policy trivially testable by simulating exceptions (no network, no real API).

Policy:
- Retry only when ``is_retryable(exc)`` is true (e.g. 429 / timeouts / 5xx).
- Give up after ``max_retries`` retries and re-raise the *original* error, so
  callers can still branch on its concrete type (e.g. a rate-limit message).
- Prefer a server ``Retry-After`` value when present; otherwise use exponential
  backoff ``backoff_base_s * 2**(attempt-1)``.
- Always add jitter and never wait below the server hint, to avoid thundering
  herds while still respecting the server's requested cooldown.
"""

from __future__ import annotations

import asyncio
import random
from collections.abc import Awaitable, Callable
from typing import TypeVar

T = TypeVar("T")

# Absolute ceiling for a single wait, so a misbehaving Retry-After header or a
# large exponent can never stall a run indefinitely.
DEFAULT_MAX_DELAY_S = 60.0


def compute_delay(
    attempt: int,
    *,
    backoff_base_s: float,
    retry_after_s: float | None,
    rng: random.Random,
    max_delay_s: float = DEFAULT_MAX_DELAY_S,
) -> float:
    """Return the sleep (seconds) before retry number ``attempt`` (1-based)."""
    if retry_after_s is not None and retry_after_s > 0:
        # Respect the server: wait at least the requested time, plus a little
        # jitter (never less) to desynchronise concurrent clients.
        delay = retry_after_s + rng.random() * min(backoff_base_s, 1.0)
    else:
        exponential = backoff_base_s * (2 ** (attempt - 1))
        # "Equal jitter": half fixed + half random, so delay stays in
        # [0.5x, 1.0x] of the exponential target (never zero).
        delay = exponential * (0.5 + rng.random() * 0.5)
    return min(delay, max_delay_s)


async def retry_async(
    func: Callable[[], Awaitable[T]],
    *,
    max_retries: int,
    backoff_base_s: float,
    is_retryable: Callable[[BaseException], bool],
    retry_after_s: Callable[[BaseException], float | None],
    sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    rng: random.Random | None = None,
    max_delay_s: float = DEFAULT_MAX_DELAY_S,
) -> T:
    """Call ``func`` with retries on transient errors.

    Non-retryable errors (per ``is_retryable``) propagate immediately, so
    unrecoverable failures such as authentication (401) or bad request (400)
    are never retried.
    """
    active_rng = rng if rng is not None else random.Random()
    attempt = 0
    while True:
        try:
            return await func()
        except BaseException as exc:  # noqa: BLE001 - re-raised unless retryable
            if not is_retryable(exc) or attempt >= max_retries:
                raise
            attempt += 1
            delay = compute_delay(
                attempt,
                backoff_base_s=backoff_base_s,
                retry_after_s=retry_after_s(exc),
                rng=active_rng,
                max_delay_s=max_delay_s,
            )
            await sleep(delay)
