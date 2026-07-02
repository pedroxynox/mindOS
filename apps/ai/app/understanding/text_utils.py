"""Pure text helpers shared by extraction, the fake provider, and metrics.

Keeping normalization in one place guarantees that a label produced by a
provider and the same label annotated in the gold set compare equal under the
exact same rules (design §13.1: "match por tipo + label normalizado").
"""

import re
import unicodedata

_WHITESPACE_RE = re.compile(r"\s+")
# Punctuation stripped from the edges of a label (keeps intra-word marks).
_PUNCT = r"\s\.,;:!?¡¿\"'`()\[\]{}\-–—"
_EDGE_PUNCT_RE = re.compile(rf"^[{_PUNCT}]+|[{_PUNCT}]+$")


def normalize_label(label: str) -> str:
    """Normalize a label for tolerant, case/accent-insensitive matching.

    Steps: lowercase, strip surrounding punctuation/whitespace, collapse inner
    whitespace, and fold accents (so "reunión" == "reunion"). Deterministic and
    pure — the same input always yields the same output.
    """
    text = label.strip().lower()
    text = _EDGE_PUNCT_RE.sub("", text)
    text = _WHITESPACE_RE.sub(" ", text).strip()
    # Fold diacritics: decompose then drop combining marks.
    decomposed = unicodedata.normalize("NFKD", text)
    folded = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return folded
