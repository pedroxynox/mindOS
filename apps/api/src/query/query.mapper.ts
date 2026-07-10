/**
 * Public wire shapes for `POST /v1/query`. The API is a thin, authenticated
 * bridge to the AI service's RAG endpoint; it reshapes the AI response into the
 * client contract (snake_case, API conventions #04) and drops anything else.
 */
export interface QuerySource {
  capture_id: string;
  snippet: string;
}

export interface QueryResponse {
  answer: string;
  sources: QuerySource[];
}

/** Raw shape returned by the AI service's /internal/query. */
export interface AiQueryPayload {
  answer?: unknown;
  sources?: unknown;
}

/** Defensively map the AI service payload into the client contract. */
export function toQueryResponse(payload: AiQueryPayload): QueryResponse {
  const answer = typeof payload.answer === 'string' ? payload.answer : '';
  const rawSources = Array.isArray(payload.sources) ? payload.sources : [];
  const sources: QuerySource[] = rawSources
    .map((s): QuerySource | null => {
      if (typeof s !== 'object' || s === null) return null;
      const rec = s as Record<string, unknown>;
      const id = rec.capture_id;
      const snippet = rec.snippet;
      if (typeof id !== 'string') return null;
      return {
        capture_id: id,
        snippet: typeof snippet === 'string' ? snippet : '',
      };
    })
    .filter((s): s is QuerySource => s !== null);
  return { answer, sources };
}
