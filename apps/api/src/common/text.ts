/**
 * Label normalisation shared by every feature that groups AI-extracted
 * entities by name (briefing people, graph entities).
 *
 * Mirrors `normalize_label` in `apps/ai/app/understanding/text_utils.py`, so
 * "Marcos", " marcos." and "MÁRCOS" fall into the same group on both sides:
 * lowercase, strip surrounding punctuation, collapse inner whitespace, fold
 * accents. Pure and deterministic.
 */
const EDGE_PUNCT = /^[\s.,;:!?¡¿"'`()[\]{}\-–—]+|[\s.,;:!?¡¿"'`()[\]{}\-–—]+$/g;

export function normalizeLabel(label: string): string {
  return label
    .toLowerCase()
    .replace(EDGE_PUNCT, '')
    .replace(/\s+/g, ' ')
    .trim()
    .normalize('NFKD')
    .replace(/\p{M}/gu, '');
}
