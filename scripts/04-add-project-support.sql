-- Migration: Add multi-project support
-- Associates features/tasks with specific projects

-- Add project_name column to project table if it doesn't exist
ALTER TABLE project
ADD COLUMN IF NOT EXISTS project_path VARCHAR(500) NULL,
ADD COLUMN IF NOT EXISTS language VARCHAR(50) NULL,
ADD COLUMN IF NOT EXISTS test_framework VARCHAR(100) NULL;

-- Add index on project name for faster lookups
CREATE INDEX IF NOT EXISTS idx_project_name ON project(name);

-- Drop and recreate view to include project info
DROP VIEW IF EXISTS vw_task_work_queue;

CREATE VIEW vw_task_work_queue AS
SELECT
    t.id as task_id,
    t.task_name,
    t.status,
    t.priority,
    s.step_type,
    s.step_text,
    sc.scenario_name,
    f.feature_name,
    p.name as project_name,
    p.project_path,
    p.language,
    p.test_framework,
    ss.display_order as step_order
FROM task t
JOIN step s ON t.step_id = s.id
JOIN scenario_step ss ON s.id = ss.step_id
JOIN scenario sc ON ss.scenario_id = sc.id
JOIN feature f ON sc.feature_id = f.id
JOIN project p ON f.project_id = p.id
WHERE t.status = 'Pending'
ORDER BY
    t.priority DESC,
    p.name,
    f.feature_name,
    sc.scenario_name,
    ss.display_order;

-- Drop and recreate stored procedure to include project info
DROP FUNCTION IF EXISTS sp_get_next_task(VARCHAR);

CREATE FUNCTION sp_get_next_task(p_agent_type VARCHAR)
RETURNS TABLE (
    task_id UUID,
    task_name VARCHAR,
    status VARCHAR,
    priority INTEGER,
    step_type VARCHAR,
    step_text TEXT,
    scenario_name VARCHAR,
    feature_name VARCHAR,
    project_name VARCHAR,
    project_path VARCHAR,
    language VARCHAR,
    test_framework VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.id,
        t.task_name,
        t.status,
        t.priority,
        s.step_type,
        s.step_text,
        sc.scenario_name,
        f.feature_name,
        p.name,
        p.project_path,
        p.language,
        p.test_framework
    FROM task t
    JOIN step s ON t.step_id = s.id
    JOIN scenario_step ss ON s.id = ss.step_id
    JOIN scenario sc ON ss.scenario_id = sc.id
    JOIN feature f ON sc.feature_id = f.id
    JOIN project p ON f.project_id = p.id
    WHERE t.status = 'Pending'
    ORDER BY
        t.priority DESC,
        p.name,
        f.feature_name,
        sc.scenario_name,
        ss.display_order
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Update CareSync project with path and language info
UPDATE project
SET
    project_path = '/Users/srowe/RiderProjects/caresync',
    language = 'csharp',
    test_framework = 'specflow'
WHERE name = 'CareSync';

COMMENT ON COLUMN project.project_path IS 'Absolute path to the project directory';
COMMENT ON COLUMN project.language IS 'Programming language (csharp, cpp, python, etc.)';
COMMENT ON COLUMN project.test_framework IS 'BDD test framework (specflow, googletest, behave, etc.)';
