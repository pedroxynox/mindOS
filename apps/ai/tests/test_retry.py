"""Tests for the async retry helper and the OpenAI error classification.

Retries are exercised entirely by simulating exceptions with an injected sleep,
so nothing here touches the network or a real OpenAI account.
"""

import random

import httpx
import pytest
from hypothesis import given
from hypothesis import strategies as st

from app.providers.openai_provider import _is_retryable, _retry_after_seconds
from app.providers.retry import compute_delay, retry_async


class _Boom(Exception):
    """A retryable stand-in error for the generic retry tests."""


class _Fatal(Exception):
    """A non-retryable stand-in error."""


def _is_boom(exc: BaseException) -> bool:
    return isinstance(exc, _Boom)


def _no_hint(_exc: BaseException) -> float | None:
    return None


async def _record_sleep(delays: list[float]):
    async def sleep(seconds: float) -> None:
        delays.append(seconds)

    return sleep


async def test_retry_succeeds_after_transient_failures() -> None:
    delays: list[float] = []
    calls = {"n": 0}

    async def flaky() -> str:
        calls["n"] += 1
        if calls["n"] < 3:
            raise _Boom("transient")
        return "ok"

    async def sleep(seconds: float) -> None:
        delays.append(seconds)

    result = await retry_async(
        flaky,
        max_retries=5,
        backoff_base_s=2.0,
        is_retryable=_is_boom,
        retry_after_s=_no_hint,
        sleep=sleep,
        rng=random.Random(0),
    )

    assert result == "ok"
    assert calls["n"] == 3  # 1 initial + 2 retries
    assert len(delays) == 2  # slept once before each retry


async def test_retry_does_not_retry_non_retryable() -> None:
    calls = {"n": 0}

    async def fatal() -> str:
        calls["n"] += 1
        raise _Fatal("nope")

    async def sleep(_seconds: float) -> None:  # pragma: no cover - never called
        raise AssertionError("should not sleep on a non-retryable error")

    with pytest.raises(_Fatal):
        await retry_async(
            fatal,
            max_retries=5,
            backoff_base_s=2.0,
            is_retryable=_is_boom,
            retry_after_s=_no_hint,
            sleep=sleep,
        )
    assert calls["n"] == 1  # tried exactly once, no retries


async def test_retry_reraises_original_after_exhausting() -> None:
    delays: list[float] = []
    calls = {"n": 0}

    async def always_fails() -> str:
        calls["n"] += 1
        raise _Boom("still failing")

    async def sleep(seconds: float) -> None:
        delays.append(seconds)

    with pytest.raises(_Boom):
        await retry_async(
            always_fails,
            max_retries=3,
            backoff_base_s=1.0,
            is_retryable=_is_boom,
            retry_after_s=_no_hint,
            sleep=sleep,
            rng=random.Random(0),
        )
    assert calls["n"] == 4  # 1 initial + 3 retries
    assert len(delays) == 3


async def test_retry_after_hint_is_respected() -> None:
    delays: list[float] = []

    async def once_then_ok() -> str:
        if not delays:
            raise _Boom("rate limited")
        return "ok"

    async def sleep(seconds: float) -> None:
        delays.append(seconds)

    def hint(_exc: BaseException) -> float | None:
        return 7.0

    result = await retry_async(
        once_then_ok,
        max_retries=2,
        backoff_base_s=2.0,
        is_retryable=_is_boom,
        retry_after_s=hint,
        sleep=sleep,
        rng=random.Random(0),
    )
    assert result == "ok"
    # Never wait below the server-requested cooldown.
    assert delays[0] >= 7.0


def test_compute_delay_uses_exponential_without_hint() -> None:
    rng = random.Random(1)
    d1 = compute_delay(1, backoff_base_s=2.0, retry_after_s=None, rng=rng)
    d2 = compute_delay(2, backoff_base_s=2.0, retry_after_s=None, rng=rng)
    # attempt 1 target = 2.0 in [1.0, 2.0]; attempt 2 target = 4.0 in [2.0, 4.0].
    assert 1.0 <= d1 <= 2.0
    assert 2.0 <= d2 <= 4.0


def test_compute_delay_caps_at_max() -> None:
    rng = random.Random(1)
    d = compute_delay(
        1, backoff_base_s=2.0, retry_after_s=10_000.0, rng=rng, max_delay_s=60.0
    )
    assert d == 60.0


@given(attempt=st.integers(min_value=1, max_value=12))
def test_compute_delay_never_exceeds_cap(attempt: int) -> None:
    """Property: the computed backoff is always within (0, max_delay_s]."""
    rng = random.Random(attempt)
    delay = compute_delay(
        attempt, backoff_base_s=2.0, retry_after_s=None, rng=rng, max_delay_s=60.0
    )
    assert 0.0 < delay <= 60.0


# --- OpenAI error classification ---------------------------------------------


def _response(status: int, headers: dict[str, str] | None = None) -> httpx.Response:
    return httpx.Response(
        status,
        headers=headers or {},
        request=httpx.Request("POST", "https://api.openai.com/v1/x"),
    )


def test_rate_limit_and_transient_are_retryable() -> None:
    from openai import (
        APIConnectionError,
        APITimeoutError,
        InternalServerError,
        RateLimitError,
    )

    request = httpx.Request("POST", "https://api.openai.com/v1/x")
    assert _is_retryable(RateLimitError("429", response=_response(429), body=None))
    assert _is_retryable(
        InternalServerError("500", response=_response(500), body=None)
    )
    assert _is_retryable(APITimeoutError(request=request))
    assert _is_retryable(APIConnectionError(request=request))


def test_auth_and_bad_request_are_not_retryable() -> None:
    from openai import AuthenticationError, BadRequestError

    assert not _is_retryable(
        AuthenticationError("401", response=_response(401), body=None)
    )
    assert not _is_retryable(
        BadRequestError("400", response=_response(400), body=None)
    )
    assert not _is_retryable(ValueError("unrelated"))


def test_retry_after_seconds_parsed_from_header() -> None:
    from openai import RateLimitError

    exc = RateLimitError(
        "429", response=_response(429, {"retry-after": "12"}), body=None
    )
    assert _retry_after_seconds(exc) == 12.0


def test_retry_after_seconds_absent_returns_none() -> None:
    from openai import RateLimitError

    exc = RateLimitError("429", response=_response(429), body=None)
    assert _retry_after_seconds(exc) is None
