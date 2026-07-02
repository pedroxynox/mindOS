"""Eval set loader (design §13.1).

Loads the versioned, hand-annotated cases from ``dataset/*.json`` into typed
:class:`EvalCase` objects. The gold labels reuse the same :class:`Extraction`
model as the predictions so scoring is apples-to-apples.
"""

import json
from dataclasses import dataclass
from pathlib import Path

from pydantic import BaseModel, Field

from app.understanding.extract import Extraction

DATASET_DIR = Path(__file__).parent / "dataset"


class EvalCase(BaseModel):
    """A single evaluation capture with hand-annotated gold labels."""

    id: str
    language: str = Field(pattern="^(es|en|mixed)$")
    description: str
    text: str
    gold: Extraction


@dataclass(frozen=True)
class EvalDataset:
    """The full, ordered eval set."""

    cases: list[EvalCase]

    def __len__(self) -> int:
        return len(self.cases)


def load_dataset(directory: Path | None = None) -> EvalDataset:
    """Load and validate every ``*.json`` case, ordered by id for determinism."""
    base = directory or DATASET_DIR
    cases: list[EvalCase] = []
    for path in sorted(base.glob("*.json")):
        raw = json.loads(path.read_text(encoding="utf-8"))
        cases.append(EvalCase.model_validate(raw))
    cases.sort(key=lambda c: c.id)
    return EvalDataset(cases=cases)
