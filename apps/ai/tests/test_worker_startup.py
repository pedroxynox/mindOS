"""The FastAPI lifespan starts/stops the comprehension worker when enabled.

These tests exercise the wiring in ``app.main`` WITHOUT any real Redis/Postgres
or the ``bullmq`` package: ``build_worker`` is monkeypatched. The lifespan only
runs when ``TestClient`` is used as a context manager, so the default
health-only path stays untouched.
"""

from fastapi.testclient import TestClient

import app.main as main_module
import app.understanding.worker as worker_module


def test_worker_disabled_by_default_health_ok(monkeypatch) -> None:
    """With the worker disabled, the app starts and /health serves normally."""
    monkeypatch.setattr(main_module.settings, "worker_enabled", False)
    built = {"called": False}

    async def spy_build_worker(settings):  # pragma: no cover - must NOT run
        built["called"] = True

    monkeypatch.setattr(worker_module, "build_worker", spy_build_worker)

    with TestClient(main_module.app) as client:
        assert client.get("/health").status_code == 200
    assert built["called"] is False


def test_worker_started_and_closed_when_enabled(monkeypatch) -> None:
    """When enabled, the lifespan builds the worker on startup and closes it."""
    state = {"built": False, "closed": False}

    class FakeWorker:
        async def close(self) -> None:
            state["closed"] = True

    async def fake_build_worker(settings) -> FakeWorker:
        state["built"] = True
        return FakeWorker()

    monkeypatch.setattr(main_module.settings, "worker_enabled", True)
    monkeypatch.setattr(worker_module, "build_worker", fake_build_worker)

    with TestClient(main_module.app) as client:
        assert client.get("/health").status_code == 200
        assert state["built"] is True
    assert state["closed"] is True


def test_worker_startup_failure_keeps_health_up(monkeypatch) -> None:
    """A worker that fails to start is swallowed; /health stays up (observable)."""

    async def boom(settings):
        raise RuntimeError("no redis reachable")

    monkeypatch.setattr(main_module.settings, "worker_enabled", True)
    monkeypatch.setattr(worker_module, "build_worker", boom)

    with TestClient(main_module.app) as client:
        assert client.get("/health").status_code == 200
