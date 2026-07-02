"""Unit + property tests for the FakeProvider extraction path."""

import pytest
from hypothesis import given
from hypothesis import strategies as st

from app.providers.fake_provider import FakeProvider
from app.understanding.extract import (
    Extraction,
    extract_entities,
    parse_extraction,
    run_extraction,
)


async def test_fake_extraction_known_input() -> None:
    provider = FakeProvider()
    ext = await extract_entities("Call Ana tomorrow to send the invoice.", provider)

    # One action item detected (imperative "Call").
    assert len(ext.tasks) == 1
    assert "Call Ana" in ext.tasks[0].label

    labels = {(e.type, e.label) for e in ext.entities}
    assert ("person", "Ana") in labels
    assert ("event", "tomorrow") in labels
    assert ("topic", "invoice") in labels


async def test_fake_extraction_is_deterministic() -> None:
    provider = FakeProvider()
    text = "Recordar a María que revise el contrato del proyecto Delta."
    first = await extract_entities(text, provider)
    second = await extract_entities(text, provider)
    assert first.model_dump() == second.model_dump()


async def test_fake_extraction_no_task_note() -> None:
    provider = FakeProvider()
    ext = await extract_entities(
        "Just some thoughts about the design of the new dashboard.", provider
    )
    assert ext.tasks == []
    assert ("topic", "design") in {(e.type, e.label) for e in ext.entities}


async def test_run_extraction_reports_zero_cost_and_latency() -> None:
    provider = FakeProvider()
    result = await run_extraction("Buy milk.", provider)
    assert isinstance(result.extraction, Extraction)
    assert result.usage.cost_usd == 0.0
    assert result.usage.provider == "fake"
    assert result.latency_ms >= 0.0


async def test_fake_embedding_is_deterministic() -> None:
    provider = FakeProvider()
    a = await provider.embed("hello world")
    b = await provider.embed("hello world")
    assert a.vector == b.vector
    assert a.dim == len(a.vector)
    assert a.usage.cost_usd == 0.0


def test_parse_extraction_rejects_malformed_json() -> None:
    with pytest.raises(ValueError):
        parse_extraction("{not valid json")


def test_parse_extraction_rejects_bad_schema() -> None:
    # 'type' outside the allowed enum must fail validation.
    with pytest.raises(ValueError):
        parse_extraction('{"entities": [{"type": "alien", "label": "x"}]}')


@given(st.text(max_size=200))
async def test_fake_extraction_never_crashes_and_is_stable(text: str) -> None:
    """For any input the fake yields valid, reproducible structured output."""
    provider = FakeProvider()
    first = await extract_entities(text, provider)
    second = await extract_entities(text, provider)
    assert first.model_dump() == second.model_dump()
    # All confidences are valid probabilities.
    for e in first.entities:
        assert 0.0 <= e.confidence <= 1.0
