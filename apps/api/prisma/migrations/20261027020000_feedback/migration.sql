-- mindOS mejoras-v2 PR D — user feedback (FR-3.5, North Star "interacciones de
-- valor") and the substrate for correcting what the AI understood (FR-2.4).
--
-- One row per (user, target): voting again on the same target replaces the
-- previous vote (upsert on the unique index). Same fail-closed RLS pattern as
-- the graph tables; must run as the table OWNER / migration role.
CREATE TABLE IF NOT EXISTS "feedback" (
    "id"          UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id"     UUID NOT NULL,
    "target_type" TEXT NOT NULL,          -- capture | query | briefing | node
    "target_id"   TEXT NOT NULL,          -- capture/node id, question, day key
    "useful"      BOOLEAN NOT NULL,
    "reason"      TEXT,
    "created_at"  TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at"  TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "feedback_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "feedback" ADD CONSTRAINT "feedback_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE UNIQUE INDEX IF NOT EXISTS "uq_feedback_user_target"
    ON "feedback" ("user_id", "target_type", "target_id");
CREATE INDEX IF NOT EXISTS "idx_feedback_user_created"
    ON "feedback" ("user_id", "created_at");

ALTER TABLE "feedback" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "feedback" FORCE  ROW LEVEL SECURITY;

CREATE POLICY "feedback_isolation" ON "feedback"
    USING      ("user_id" = NULLIF(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK ("user_id" = NULLIF(current_setting('app.current_user_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON "feedback" TO "mindos_app";
