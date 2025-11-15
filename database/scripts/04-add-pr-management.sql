-- Add PR management tables and functions
-- This supports the parallel worktree workflow with automated PR management

-- Table to track PR fix attempts (prevent infinite loops)
CREATE TABLE IF NOT EXISTS pr_fix_attempts (
    id SERIAL PRIMARY KEY,
    pr_number INTEGER NOT NULL,
    attempted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    fix_successful BOOLEAN DEFAULT NULL,
    error_message TEXT,
    CONSTRAINT pr_fix_attempts_unique UNIQUE (pr_number, attempted_at)
);

CREATE INDEX IF NOT EXISTS idx_pr_fix_attempts_pr_number ON pr_fix_attempts(pr_number);
CREATE INDEX IF NOT EXISTS idx_pr_fix_attempts_attempted_at ON pr_fix_attempts(attempted_at DESC);

-- Add columns to task table for PR tracking
ALTER TABLE task
ADD COLUMN IF NOT EXISTS pr_number INTEGER,
ADD COLUMN IF NOT EXISTS pr_url TEXT,
ADD COLUMN IF NOT EXISTS branch_name TEXT,
ADD COLUMN IF NOT EXISTS worktree_path TEXT,
ADD COLUMN IF NOT EXISTS merged_at TIMESTAMP;

-- Add index for PR lookups
CREATE INDEX IF NOT EXISTS idx_task_pr_number ON task(pr_number) WHERE pr_number IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_task_branch_name ON task(branch_name) WHERE branch_name IS NOT NULL;

-- Update task status enum to include PR-related states
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_status') THEN
        CREATE TYPE task_status AS ENUM ('pending', 'in_progress', 'completed', 'failed', 'pr_created', 'pr_fixing', 'merged');
    ELSE
        -- Add new values if they don't exist
        BEGIN
            ALTER TYPE task_status ADD VALUE IF NOT EXISTS 'pr_created';
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;

        BEGIN
            ALTER TYPE task_status ADD VALUE IF NOT EXISTS 'pr_fixing';
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;

        BEGIN
            ALTER TYPE task_status ADD VALUE IF NOT EXISTS 'merged';
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
    END IF;
END $$;

-- Function to get PRs that need review processing
CREATE OR REPLACE FUNCTION get_prs_needing_review()
RETURNS TABLE (
    pr_number INTEGER,
    branch_name TEXT,
    task_id UUID,
    feature_name TEXT,
    scenario_name TEXT,
    step_text TEXT,
    step_type TEXT,
    created_at TIMESTAMP,
    last_fix_attempt TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.pr_number,
        t.branch_name,
        t.id as task_id,
        f.feature_name as feature_name,
        sc.scenario_name as scenario_name,
        s.step_text,
        s.step_type,
        t.created_at,
        (SELECT MAX(attempted_at) FROM pr_fix_attempts WHERE pr_fix_attempts.pr_number = t.pr_number) as last_fix_attempt
    FROM task t
    LEFT JOIN step s ON t.step_id = s.id
    LEFT JOIN scenario_step ss ON s.id = ss.step_id
    LEFT JOIN scenario sc ON ss.scenario_id = sc.id
    LEFT JOIN feature f ON sc.feature_id = f.id
    WHERE t.status IN ('pr_created', 'pr_fixing')
        AND t.pr_number IS NOT NULL
    ORDER BY t.created_at ASC;
END;
$$ LANGUAGE plpgsql;

-- Function to check if a PR has reached max fix attempts
CREATE OR REPLACE FUNCTION has_reached_max_fix_attempts(
    p_pr_number INTEGER,
    p_max_attempts INTEGER DEFAULT 3
)
RETURNS BOOLEAN AS $$
DECLARE
    v_attempt_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_attempt_count
    FROM pr_fix_attempts
    WHERE pr_number = p_pr_number;

    RETURN v_attempt_count >= p_max_attempts;
END;
$$ LANGUAGE plpgsql;

-- Function to record successful PR merge
CREATE OR REPLACE FUNCTION record_pr_merge(
    p_pr_number INTEGER,
    p_merge_commit_sha TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    UPDATE task
    SET
        status = 'merged',
        merged_at = NOW(),
        updated_at = NOW()
    WHERE pr_number = p_pr_number;

    -- Log the merge
    INSERT INTO pr_fix_attempts (pr_number, attempted_at, fix_successful, error_message)
    VALUES (p_pr_number, NOW(), TRUE, 'Successfully merged: ' || COALESCE(p_merge_commit_sha, 'unknown'));
END;
$$ LANGUAGE plpgsql;

-- View for PR dashboard
CREATE OR REPLACE VIEW vw_pr_dashboard AS
SELECT
    t.id as task_id,
    t.pr_number,
    t.pr_url,
    t.branch_name,
    t.status,
    s.step_type,
    sc.scenario_name as scenario_name,
    f.feature_name as feature_name,
    s.step_text,
    t.created_at,
    t.merged_at,
    COALESCE(fix_stats.attempt_count, 0) as fix_attempt_count,
    fix_stats.last_fix_attempt,
    fix_stats.has_failures,
    CASE
        WHEN t.status = 'merged' THEN 'Merged'
        WHEN fix_stats.attempt_count >= 3 THEN 'Needs Manual Review'
        WHEN fix_stats.has_failures THEN 'Auto-Fix Failed'
        WHEN t.status = 'pr_fixing' THEN 'Fixing Issues'
        WHEN t.status = 'pr_created' THEN 'Awaiting Review'
        ELSE 'Unknown'
    END as pr_status_summary
FROM task t
LEFT JOIN step s ON t.step_id = s.id
LEFT JOIN scenario_step ss ON s.id = ss.step_id
LEFT JOIN scenario sc ON ss.scenario_id = sc.id
LEFT JOIN feature f ON sc.feature_id = f.id
LEFT JOIN (
    SELECT
        pr_number,
        COUNT(*) as attempt_count,
        MAX(attempted_at) as last_fix_attempt,
        BOOL_OR(fix_successful = FALSE) as has_failures
    FROM pr_fix_attempts
    GROUP BY pr_number
) fix_stats ON t.pr_number = fix_stats.pr_number
WHERE t.pr_number IS NOT NULL
ORDER BY t.created_at DESC;

-- Grant permissions
GRANT SELECT ON vw_pr_dashboard TO PUBLIC;
GRANT EXECUTE ON FUNCTION get_prs_needing_review() TO PUBLIC;
GRANT EXECUTE ON FUNCTION has_reached_max_fix_attempts(INTEGER, INTEGER) TO PUBLIC;
GRANT EXECUTE ON FUNCTION record_pr_merge(INTEGER, TEXT) TO PUBLIC;

-- Add comments
COMMENT ON TABLE pr_fix_attempts IS 'Tracks automated fix attempts for PRs to prevent infinite loops';
COMMENT ON COLUMN task.pr_number IS 'GitHub pull request number';
COMMENT ON COLUMN task.pr_url IS 'Full URL to the pull request';
COMMENT ON COLUMN task.branch_name IS 'Git branch name for this task';
COMMENT ON COLUMN task.worktree_path IS 'Path to git worktree used for this task';
COMMENT ON COLUMN task.merged_at IS 'Timestamp when PR was merged to main';
COMMENT ON FUNCTION get_prs_needing_review() IS 'Returns all PRs that need review processing by the daemon';
COMMENT ON FUNCTION has_reached_max_fix_attempts(INTEGER, INTEGER) IS 'Checks if a PR has reached the maximum number of automated fix attempts';
COMMENT ON FUNCTION record_pr_merge(INTEGER, TEXT) IS 'Records a successful PR merge in the database';
COMMENT ON VIEW vw_pr_dashboard IS 'Dashboard view of all PRs with their current status and fix attempts';
