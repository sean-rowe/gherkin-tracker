-- Add BDD Step Implementation Tracking
-- This migration adds fields to track BDD step definition implementation separately from business logic

-- Add columns to task table for BDD tracking
ALTER TABLE task ADD COLUMN IF NOT EXISTS bdd_step_file VARCHAR(1000) NULL;
ALTER TABLE task ADD COLUMN IF NOT EXISTS bdd_method_name VARCHAR(255) NULL;
ALTER TABLE task ADD COLUMN IF NOT EXISTS bdd_implemented BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE task ADD COLUMN IF NOT EXISTS bdd_implementation_notes TEXT NULL;

-- Add columns to track business logic implementation separately
ALTER TABLE task ADD COLUMN IF NOT EXISTS business_logic_implemented BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE task ADD COLUMN IF NOT EXISTS service_location VARCHAR(1000) NULL;

-- Add comment
COMMENT ON COLUMN task.bdd_step_file IS 'Path to the step definition file (e.g., UserAuthenticationSteps.cs)';
COMMENT ON COLUMN task.bdd_method_name IS 'Name of the step definition method';
COMMENT ON COLUMN task.bdd_implemented IS 'TRUE if BDD step definition exists with real implementation';
COMMENT ON COLUMN task.bdd_implementation_notes IS 'Notes about the BDD step implementation';
COMMENT ON COLUMN task.business_logic_implemented IS 'TRUE if the underlying business logic (service/controller) is implemented';
COMMENT ON COLUMN task.service_location IS 'Path to the service/controller implementing the business logic';

-- Update the sp_complete_task function to require BDD implementation
CREATE OR REPLACE FUNCTION sp_complete_task(
    p_task_id UUID,
    p_agent_id UUID,
    p_work_accomplished TEXT,
    p_build_succeeded BOOLEAN,
    p_tests_passed BOOLEAN,
    p_bdd_step_file VARCHAR DEFAULT NULL,
    p_bdd_method_name VARCHAR DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
    v_started_at TIMESTAMP;
    v_bdd_implemented BOOLEAN;
BEGIN
    -- Get started_at time
    SELECT started_at INTO v_started_at FROM task WHERE id = p_task_id;

    -- Determine if BDD is properly implemented
    v_bdd_implemented := (p_bdd_step_file IS NOT NULL AND p_bdd_method_name IS NOT NULL);

    -- Update task
    UPDATE task
    SET status = CASE
            WHEN v_bdd_implemented AND p_tests_passed THEN 'Completed'
            WHEN v_bdd_implemented AND NOT p_tests_passed THEN 'Failed'
            ELSE 'Pending'  -- If no BDD step, can't be truly complete
        END,
        completed_at = CASE WHEN v_bdd_implemented AND p_tests_passed THEN CURRENT_TIMESTAMP ELSE NULL END,
        updated_at = CURRENT_TIMESTAMP,
        actual_minutes = EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_started_at))/60,
        bdd_step_file = p_bdd_step_file,
        bdd_method_name = p_bdd_method_name,
        bdd_implemented = v_bdd_implemented,
        business_logic_implemented = p_build_succeeded
    WHERE id = p_task_id;

    -- Update agent
    UPDATE agent
    SET status = CASE
            WHEN v_bdd_implemented AND p_tests_passed THEN 'Completed'
            ELSE 'Failed'
        END,
        current_task_id = NULL,
        completed_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_agent_id;

    -- Update history
    UPDATE agent_task_history
    SET completed_at = CURRENT_TIMESTAMP,
        status = CASE
            WHEN v_bdd_implemented AND p_tests_passed THEN 'Completed'
            WHEN v_bdd_implemented AND NOT p_tests_passed THEN 'Failed'
            ELSE 'Abandoned'
        END,
        work_accomplished = p_work_accomplished,
        build_succeeded = p_build_succeeded,
        tests_passed = p_tests_passed
    WHERE agent_id = p_agent_id AND task_id = p_task_id AND completed_at IS NULL;
END;
$$ LANGUAGE plpgsql;

-- Create new view showing BDD implementation status
CREATE OR REPLACE VIEW vw_bdd_implementation_status AS
SELECT
    f.feature_name,
    sc.scenario_name,
    st.step_type,
    st.step_text,
    t.status,
    t.bdd_implemented,
    t.bdd_step_file,
    t.bdd_method_name,
    t.business_logic_implemented,
    t.service_location,
    t.code_location,
    CASE
        WHEN t.bdd_implemented AND t.business_logic_implemented THEN 'FULLY_IMPLEMENTED'
        WHEN t.bdd_implemented AND NOT t.business_logic_implemented THEN 'BDD_ONLY'
        WHEN NOT t.bdd_implemented AND t.business_logic_implemented THEN 'BUSINESS_LOGIC_ONLY'
        ELSE 'NOT_IMPLEMENTED'
    END as implementation_status
FROM feature f
JOIN scenario sc ON f.id = sc.feature_id
JOIN scenario_step ss ON sc.id = ss.scenario_id
JOIN step st ON ss.step_id = st.id
JOIN task t ON st.id = t.step_id
WHERE f.is_active = TRUE;

-- Create view showing tasks that need BDD step implementations
CREATE OR REPLACE VIEW vw_tasks_needing_bdd AS
SELECT
    t.id as task_id,
    t.task_name,
    t.status,
    t.priority,
    st.step_type,
    st.step_text,
    sc.scenario_name,
    f.feature_name,
    f.file_name,
    t.business_logic_implemented,
    t.service_location
FROM task t
JOIN step st ON t.step_id = st.id
JOIN scenario_step ss ON st.id = ss.step_id
JOIN scenario sc ON ss.scenario_id = sc.id
JOIN feature f ON sc.feature_id = f.id
WHERE t.bdd_implemented = FALSE
AND f.is_active = TRUE
ORDER BY t.priority DESC, f.feature_name, sc.scenario_name, ss.display_order;

-- Create view showing fully implemented features
CREATE OR REPLACE VIEW vw_feature_bdd_progress AS
SELECT
    f.id AS feature_id,
    f.feature_name,
    f.file_name,
    COUNT(DISTINCT t.id) AS total_tasks,
    COUNT(DISTINCT CASE WHEN t.bdd_implemented THEN t.id END) AS bdd_implemented_count,
    COUNT(DISTINCT CASE WHEN t.business_logic_implemented THEN t.id END) AS business_logic_count,
    COUNT(DISTINCT CASE WHEN t.bdd_implemented AND t.business_logic_implemented THEN t.id END) AS fully_implemented_count,
    ROUND(COUNT(DISTINCT CASE WHEN t.bdd_implemented THEN t.id END)::numeric /
          NULLIF(COUNT(DISTINCT t.id), 0) * 100, 1) AS bdd_completion_pct,
    ROUND(COUNT(DISTINCT CASE WHEN t.business_logic_implemented THEN t.id END)::numeric /
          NULLIF(COUNT(DISTINCT t.id), 0) * 100, 1) AS business_logic_completion_pct,
    ROUND(COUNT(DISTINCT CASE WHEN t.bdd_implemented AND t.business_logic_implemented THEN t.id END)::numeric /
          NULLIF(COUNT(DISTINCT t.id), 0) * 100, 1) AS full_completion_pct
FROM feature f
JOIN scenario sc ON f.id = sc.feature_id
JOIN scenario_step ss ON sc.id = ss.scenario_id
JOIN step st ON ss.step_id = st.id
JOIN task t ON st.id = t.step_id
WHERE f.is_active = TRUE
GROUP BY f.id, f.feature_name, f.file_name;

-- Update existing completed tasks based on current data
UPDATE task
SET bdd_implemented = TRUE,
    bdd_step_file = code_location
WHERE status = 'Completed' AND code_location IS NOT NULL;

-- Add index for BDD implementation queries
CREATE INDEX IF NOT EXISTS idx_task_bdd_implemented ON task(bdd_implemented);
CREATE INDEX IF NOT EXISTS idx_task_business_logic_implemented ON task(business_logic_implemented);

-- Confirmation
SELECT 'BDD tracking schema migration completed successfully' AS status;
