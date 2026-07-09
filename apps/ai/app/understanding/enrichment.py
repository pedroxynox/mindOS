"""Pure mapping from an :class:`Extraction` to a graph enrichment *plan*.

This is the deterministic heart of the GraphWriter (design §8.3), kept as a pure
function so its correctness properties can be verified offline (no DB, no
network): idempotency of the shape (P-COMP-2), total provenance (P-COMP-3), and
"the AI proposes, never confirms" (P-COMP-6). The :class:`GraphWriter` (§6) only
*executes* this plan against Postgres under RLS; all the judgement lives here.

The plan speaks in **dedup keys and labels**, never in database ids (which are
assigned at write time). A node's ``dedup_key`` is a deterministic hash of
``(user_id, capture_id, node_type, normalized_label)`` so reprocessing the same
capture produces the exact same keys → ``ON CONFLICT DO NOTHING`` at write time
yields no duplicates.
"""

import hashlib
from dataclasses import dataclass, field

from app.understanding.extract import Extraction
from app.understanding.text_utils import normalize_label

# Sentinel edge endpoint meaning "the source Capture node" (whose id the writer
# already knows). Used as the target of every ``derived_from`` provenance edge.
CAPTURE_REF = "__capture__"

# Node types the extraction can yield (task is folded in from Extraction.tasks).
_TASK_TYPE = "task"


@dataclass(frozen=True)
class NodePlan:
    """A derived node to upsert (origin='ai'), addressed by its dedup key."""

    node_type: str
    title: str
    dedup_key: str
    confidence: float
    attributes: dict = field(default_factory=dict)


@dataclass(frozen=True)
class EdgePlan:
    """A derived edge to upsert (origin='ai', user_confirmed=false).

    ``source``/``target`` are node dedup keys, or :data:`CAPTURE_REF` for the
    source capture. The writer resolves these to node ids.
    """

    type: str
    source: str
    target: str
    confidence: float


@dataclass(frozen=True)
class EnrichmentPlan:
    """The full, deterministic shape to write for one capture."""

    nodes: tuple[NodePlan, ...]
    edges: tuple[EdgePlan, ...]


def dedup_key(user_id: str, capture_id: str, node_type: str, label: str) -> str:
    """Deterministic natural key for a derived node (design §8.3).

    Same (user, capture, type, normalized label) → same key, always. This is the
    basis of write-time idempotency (P-COMP-2). Uses a unit-separator between
    fields so distinct fields cannot collide by concatenation.
    """
    norm = normalize_label(label)
    material = "\x1f".join([user_id, capture_id, node_type, norm])
    return hashlib.sha256(material.encode("utf-8")).hexdigest()


def build_enrichment_plan(
    user_id: str, capture_id: str, extraction: Extraction
) -> EnrichmentPlan:
    """Turn a validated :class:`Extraction` into a deterministic write plan.

    - Every task becomes a ``task`` node; every entity becomes a node of its
      type. Duplicates (same type + normalized label) collapse to one node.
    - Every derived node gets exactly one ``derived_from`` edge to the capture
      (provenance is mandatory — P-COMP-3).
    - Each extracted connection becomes a semantic edge **only if both endpoints
      resolve to nodes we actually extracted** (design §8.3); otherwise it is
      dropped (never invent an endpoint).
    """
    nodes_by_key: dict[str, NodePlan] = {}
    # normalized label -> list of (node_type, dedup_key), for connection resolution.
    label_index: dict[str, list[tuple[str, str]]] = {}

    def add_node(node_type: str, label: str, confidence: float) -> str | None:
        title = label.strip()
        if not title:
            return None
        key = dedup_key(user_id, capture_id, node_type, label)
        if key not in nodes_by_key:
            nodes_by_key[key] = NodePlan(
                node_type=node_type,
                title=title,
                dedup_key=key,
                confidence=confidence,
                attributes={"dedup_key": key},
            )
            label_index.setdefault(normalize_label(label), []).append(
                (node_type, key)
            )
        return key

    # 1) Nodes — tasks first (so a task/entity sharing a label keeps the task
    #    node too, addressed under a different type), then typed entities.
    for task in extraction.tasks:
        add_node(_TASK_TYPE, task.label, task.confidence)
    for ent in extraction.entities:
        add_node(ent.type, ent.label, ent.confidence)

    # 2) Provenance — one derived_from per node, pointing at the capture.
    edges_by_key: dict[tuple[str, str, str], EdgePlan] = {}

    def add_edge(etype: str, source: str, target: str, confidence: float) -> None:
        if source == target:
            return  # never a self-loop
        key = (etype, source, target)
        if key not in edges_by_key:
            edges_by_key[key] = EdgePlan(
                type=etype, source=source, target=target, confidence=confidence
            )

    for node in nodes_by_key.values():
        add_edge("derived_from", node.dedup_key, CAPTURE_REF, node.confidence)

    # 3) Semantic edges — resolve both endpoints to extracted nodes or drop.
    for conn in extraction.connections:
        target_prefer = "person" if conn.type == "assigned_to" else None
        source_key = _resolve_endpoint(label_index, conn.source, prefer=_TASK_TYPE)
        target_key = _resolve_endpoint(label_index, conn.target, prefer=target_prefer)
        if source_key is None or target_key is None:
            continue  # an endpoint we did not extract → do not invent it
        add_edge(conn.type, source_key, target_key, conn.confidence)

    return EnrichmentPlan(
        nodes=tuple(nodes_by_key.values()),
        edges=tuple(edges_by_key.values()),
    )


def _resolve_endpoint(
    label_index: dict[str, list[tuple[str, str]]],
    label: str,
    *,
    prefer: str | None,
) -> str | None:
    """Resolve a connection endpoint label to a node dedup key, or ``None``.

    Prefers a node of type ``prefer`` when several types share the same
    normalized label (e.g. ``assigned_to`` targets a person); otherwise returns
    the first extracted node with that label.
    """
    candidates = label_index.get(normalize_label(label))
    if not candidates:
        return None
    if prefer is not None:
        for node_type, key in candidates:
            if node_type == prefer:
                return key
    return candidates[0][1]
