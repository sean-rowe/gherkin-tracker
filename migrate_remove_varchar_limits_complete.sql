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

-- Step 3: Recreate views

-- View: Complete feature details with all scenarios, steps, and tasks
CREATE VIEW vw_feature_complete AS
SELECT
    f.id AS feature_id,
    f.feature_name,
    f.file_name,
    f.as_a,
    f.i_want,
    f.so_that,
    s.id AS scenario_id,
    s.scenario_name,
    s.display_order AS scenario_order,
    st.id AS step_id,
    st.step_type,
    st.step_text,
    ss.display_order AS step_order,
    ss.parameters,
    t.id AS task_id,
    t.status AS task_status,
    t.assigned_agent_id
FROM feature f
LEFT JOIN scenario s ON f.id = s.feature_id
LEFT JOIN scenario_step ss ON s.id = ss.scenario_id
LEFT JOIN step st ON ss.step_id = st.id
LEFT JOIN task t ON st.id = t.step_id
WHERE f.is_active = TRUE;

-- View: Task work queue (incomplete tasks ordered by priority)
CREATE VIEW vw_task_work_queue AS
SELECT
    t.id AS task_id,
    t.task_name,
    t.status,
    t.priority,
    t.assigned_agent_id,
    st.step_type,
    st.step_text,
    s.scenario_name,
    f.feature_name,
    f.file_name
FROM task t
INNER JOIN step st ON t.step_id = st.id
INNER JOIN scenario_step ss ON st.id = ss.step_id
INNER JOIN scenario s ON ss.scenario_id = s.id
INNER JOIN feature f ON s.feature_id = f.id
WHERE t.status IN ('Pending', 'InProgress', 'Blocked')
AND f.is_active = TRUE;

-- View: Agent current workload
CREATE VIEW vw_agent_workload AS
SELECT
    a.id AS agent_id,
    a.agent_name,
    a.agent_type,
    a.status,
    a.started_at,
    a.last_heartbeat,
    t.task_name,
    t.status AS task_status,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - a.started_at))/60 AS minutes_working
FROM agent a
LEFT JOIN task t ON a.current_task_id = t.id
WHERE a.status IN ('Working', 'Idle');

-- View: Feature completion statistics
CREATE VIEW vw_feature_progress AS
SELECT
    f.id AS feature_id,
    f.feature_name,
    f.file_name,
    COUNT(DISTINCT s.id) AS total_scenarios,
    COUNT(DISTINCT CASE WHEN s.status = 'Completed' THEN s.id END) AS completed_scenarios,
    COUNT(DISTINCT t.id) AS total_tasks,
    COUNT(DISTINCT CASE WHEN t.status = 'Completed' THEN t.id END) AS completed_tasks,
    CASE
        WHEN COUNT(DISTINCT t.id) = 0 THEN 0
        ELSE CAST(COUNT(DISTINCT CASE WHEN t.status = 'Completed' THEN t.id END) AS FLOAT) /
             COUNT(DISTINCT t.id) * 100
    END AS completion_percentage
FROM feature f
LEFT JOIN scenario s ON f.id = s.feature_id
LEFT JOIN scenario_step ss ON s.id = ss.scenario_id
LEFT JOIN step st ON ss.step_id = st.id
LEFT JOIN task t ON st.id = t.step_id
WHERE f.is_active = TRUE
GROUP BY f.id, f.feature_name, f.file_name;

-- View: BDD implementation status
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

-- View: Tasks that need BDD step implementations
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

-- View: Feature BDD progress
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

COMMIT;

-- Verify changes
SELECT 'Migration completed successfully!' AS status;
SELECT
    table_name,
    column_name,
    data_type,
    character_maximum_length
FROM information_schema.columns
WHERE table_name IN ('feature', 'scenario', 'step', 'task')
AND column_name IN ('as_a', 'i_want', 'so_that', 'tags', 'file_path', 'step_text', 'description')
ORDER BY table_name, column_name;
