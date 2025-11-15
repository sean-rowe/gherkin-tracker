-- Migration: Remove varchar limits that are too restrictive
-- Changes varchar(1000) to TEXT for fields that can legitimately be long

BEGIN;

-- Step 1: Drop views that depend on the columns we're changing
DROP VIEW IF EXISTS vw_feature_complete CASCADE;
DROP VIEW IF EXISTS vw_feature_progress CASCADE;
DROP VIEW IF EXISTS vw_feature_bdd_progress CASCADE;
DROP VIEW IF EXISTS vw_task_work_queue CASCADE;
DROP VIEW IF EXISTS vw_agent_workload CASCADE;
DROP VIEW IF EXISTS vw_tasks_needing_bdd CASCADE;
DROP VIEW IF EXISTS vw_bdd_implementation_status CASCADE;

-- Step 2: Alter column types
-- Feature table: Allow unlimited length for user story fields and tags
ALTER TABLE feature ALTER COLUMN as_a TYPE TEXT;
ALTER TABLE feature ALTER COLUMN i_want TYPE TEXT;
ALTER TABLE feature ALTER COLUMN so_that TYPE TEXT;
ALTER TABLE feature ALTER COLUMN tags TYPE TEXT;
ALTER TABLE feature ALTER COLUMN file_path TYPE TEXT;

-- Scenario table: Allow unlimited length for tags
ALTER TABLE scenario ALTER COLUMN tags TYPE TEXT;

-- Step table: Allow unlimited length for step text (some steps can be very descriptive)
ALTER TABLE step ALTER COLUMN step_text TYPE TEXT;

-- Task table: Allow unlimited length for description and notes
ALTER TABLE task ALTER COLUMN description TYPE TEXT;

-- Agent table: Allow unlimited length for notes (if exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name='agent' AND column_name='notes') THEN
        ALTER TABLE agent ALTER COLUMN notes TYPE TEXT;
    END IF;
END $$;

COMMIT;

-- Verify changes
\d feature
\d scenario
\d step
\d task
\d agent
