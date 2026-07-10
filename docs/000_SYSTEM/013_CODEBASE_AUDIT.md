# 013 — Codebase Audit (2026-07-10)

> Deep hygiene audit of the whole monorepo (mobile / api / ai). Goal: remove
> dead code, confirm consistency, security and git hygiene, and record findings
> so the codebase stays clean and scalable. No product behaviour was changed.

## Scope & method

- **apps/mobile** (Flutter): `flutter analyze`, `flutter test`, dependency-usage
  scan, dead-file/import search, debug-artifact search.
- **apps/api** (NestJS): `tsc --noEmit`, unit tests, debug-artifact search.
- **apps/ai** (Python/FastAPI): debug-artifact search, existing pytest suite.
- **repo**: secret scan, `.gitignore` correctness, tracked-artifact scan.

## Changes made in this pass

| Area | Action | Rationale |
|------|--------|-----------|
| Dead feature | **Removed the `health` feature** (`lib/src/features/health/health_providers.dart`, `health_repository.dart`) and its test | The API health ping was dropped from the UI when the "Hoy" dashboard was rebuilt; nothing imported these files anymore. The backend `/v1/health` endpoint (used by Render health checks) is unaffected. |

That was the only dead code found. Everything else was already clean.

## Findings by area

- **Dead code / unused files:** Only the `health` feature (removed). All other
  `lib/` files are reachable; `flutter analyze` reports **no unused imports or
  dead elements**.
- **Debug artifacts:** No `print`/`debugPrint`/`console.log`/`debugger`/`pdb`,
  no `TODO`/`FIXME`/`HACK`, no commented-out code blocks in any of the three
  apps.
- **Dependencies (mobile):** All declared packages are used. `sqlite3_flutter_libs`
  has no Dart import by design (native SQLite runtime for Drift on mobile) — kept.
  Versions are intentionally pinned for reproducible builds (D-001).
- **Security:** No secrets, API keys or credentials in source. All secrets are
  injected via environment (`sync: false` / `generateValue` in `render.yaml`).
  The only pattern matches were test fixtures and certificates inside
  `node_modules` (not tracked).
- **Git hygiene:** No `.env`, `node_modules/`, `build/`, `*.g.dart`, `dist/` or
  `__pycache__` tracked. `.gitignore` files are correct.
- **Documentation:** Every source file already opens with a purpose/responsibility
  comment; public APIs are documented in English. Docs are organised under
  `docs/000_SYSTEM` + numbered domains — no empty/contradictory files found.
- **Testing:** Mobile 15 tests, API unit tests per module, AI 107 tests — all
  green after the cleanup.

## Recommendations (not done — deliberate, for reviewable follow-up PRs)

These are safe improvements intentionally deferred so each lands as a small,
behaviour-preserving PR:

1. **Unify the two authenticated HTTP clients.** `GraphApiClient` (graph /
   briefing / query) and `MindosApi` (tasks / growth / finance) both implement
   auth-header + error mapping. Fold `GraphApiClient` onto `MindosApi` to remove
   the duplication. *Touches several call sites → its own PR.*
2. **Extract a shared date/number formatter.** The Spanish month array +
   `HH:mm` / `d mmm` formatting is repeated in `briefing_card`, `tasks_screen`,
   `growth_screen` and `home_screen`. Extract to `lib/src/widgets` or a `format`
   util.
3. **Per-user timezone** for briefing/finance day bucketing (currently UTC).
4. **Dependency freshness:** 21 mobile packages have newer majors available;
   upgrade deliberately (behind tests) rather than automatically, to preserve
   reproducibility.

## Verdict

The codebase is in strong shape: analyzer/type-clean, well-documented, tested,
no secrets, correct git hygiene. This pass removed the single dead feature and
recorded a short, prioritised list of DRY/quality follow-ups.
