-- Gherkin Tracker Database Schema for PostgreSQL
-- Tracks Gherkin features, scenarios, steps, and implementation tasks

-- ============================================================================
-- TABLE: Project
-- Top-level container for all project requirements and specifications
-- ============================================================================
CREATE TABLE project (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT NULL,
    technical_specs TEXT NULL,
    business_requirements TEXT NULL,
    target_platforms VARCHAR(500) NULL,
    technology_stack TEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_project_name UNIQUE (name)
);

CREATE INDEX idx_project_is_active ON project(is_active);

-- ============================================================================
-- TABLE: Epic
-- Agile epic containing multiple features
-- ============================================================================
CREATE TABLE epic (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL,
    name VARCHAR(500) NOT NULL,
    description TEXT NULL,
    business_value TEXT NULL,
    acceptance_criteria TEXT NULL,
    priority INTEGER NOT NULL DEFAULT 0, -- Higher number = higher priority
    status VARCHAR(50) NOT NULL DEFAULT 'Pending', -- Pending, InProgress, Completed, Blocked
    start_date TIMESTAMP NULL,
    target_date TIMESTAMP NULL,
    completed_date TIMESTAMP NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_epic_project FOREIGN KEY (project_id) REFERENCES project(id)
);

CREATE INDEX idx_epic_project_id ON epic(project_id);
CREATE INDEX idx_epic_status ON epic(status);
CREATE INDEX idx_epic_priority ON epic(priority);

-- ============================================================================
-- TABLE: Feature
-- Gherkin Feature - maps to .feature files
-- Contains: Feature: <name> / As a <role> I want <goal> So that <benefit>
-- ============================================================================
CREATE TABLE feature (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    epic_id UUID NULL, -- Optional: may not belong to an epic
    project_id UUID NOT NULL,
    file_name VARCHAR(500) NOT NULL, -- e.g., "UserAuthentication.feature"
    file_path VARCHAR(1000) NULL, -- Relative path in project
    feature_name VARCHAR(500) NOT NULL,
    as_a VARCHAR(500) NULL, -- "As a <role>"
    i_want VARCHAR(1000) NULL, -- "I want <goal>"
    so_that VARCHAR(1000) NULL, -- "So that <benefit>"
    description TEXT NULL, -- Additional feature documentation
    background TEXT NULL, -- Gherkin Background steps (common setup)
    tags VARCHAR(1000) NULL, -- Comma-separated tags (e.g., "@smoke, @critical")
    priority INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(50) NOT NULL DEFAULT 'Pending', -- Pending, InProgress, Completed, Blocked
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_feature_epic FOREIGN KEY (epic_id) REFERENCES epic(id),
    CONSTRAINT fk_feature_project FOREIGN KEY (project_id) REFERENCES project(id),
    CONSTRAINT uq_feature_filename_project UNIQUE (file_name, project_id)
);

CREATE INDEX idx_feature_epic_id ON feature(epic_id);
CREATE INDEX idx_feature_project_id ON feature(project_id);
CREATE INDEX idx_feature_status ON feature(status);

-- ============================================================================
-- TABLE: Scenario
-- Gherkin Scenario - business-level user interaction
-- Written as user actions: "the user does X", "the system is in X state"
-- ============================================================================
CREATE TABLE scenario (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feature_id UUID NOT NULL,
    scenario_name VARCHAR(500) NOT NULL,
    description TEXT NULL, -- Business perspective description
    scenario_type VARCHAR(50) NOT NULL DEFAULT 'Scenario', -- Scenario, ScenarioOutline
    tags VARCHAR(1000) NULL, -- Comma-separated tags
    display_order INTEGER NOT NULL, -- Order within the feature file
    priority INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(50) NOT NULL DEFAULT 'Pending', -- Pending, InProgress, Completed, Blocked, Failed
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_scenario_feature FOREIGN KEY (feature_id) REFERENCES feature(id) ON DELETE CASCADE
);

CREATE INDEX idx_scenario_feature_id ON scenario(feature_id);
CREATE INDEX idx_scenario_status ON scenario(status);
CREATE INDEX idx_scenario_display_order ON scenario(display_order);

-- ============================================================================
-- TABLE: Step
-- Reusable Gherkin steps (Given/When/Then/And/But)
-- Deduplicated to enable step reuse across scenarios
-- ============================================================================
CREATE TABLE step (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    step_type VARCHAR(20) NOT NULL, -- Given, When, Then, And, But, Example
    step_text VARCHAR(2000) NOT NULL, -- Parameterized step text with <placeholders>
    description TEXT NULL, -- Technical description of what this step does
    is_reusable BOOLEAN NOT NULL DEFAULT TRUE, -- Whether this step can be reused
    implementation_notes TEXT NULL, -- Notes on how to implement
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usage_count INTEGER NOT NULL DEFAULT 0, -- Track how many scenarios use this step
    CONSTRAINT chk_step_step_type CHECK (step_type IN ('Given', 'When', 'Then', 'And', 'But', 'Example'))
);

CREATE INDEX idx_step_step_type ON step(step_type);
CREATE INDEX idx_step_usage_count ON step(usage_count);

-- ============================================================================
-- TABLE: ScenarioStep
-- Maps scenarios to steps in order
-- Enables step reuse while maintaining scenario-specific order
-- ============================================================================
CREATE TABLE scenario_step (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scenario_id UUID NOT NULL,
    step_id UUID NOT NULL,
    display_order INTEGER NOT NULL, -- Order of step within the scenario
    parameters TEXT NULL, -- JSON or delimited string of parameter values
    example_values TEXT NULL, -- For Scenario Outlines: example data
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_scenariostep_scenario FOREIGN KEY (scenario_id) REFERENCES scenario(id) ON DELETE CASCADE,
    CONSTRAINT fk_scenariostep_step FOREIGN KEY (step_id) REFERENCES step(id),
    CONSTRAINT uq_scenariostep_order UNIQUE (scenario_id, display_order)
);

CREATE INDEX idx_scenariostep_scenario_id ON scenario_step(scenario_id);
CREATE INDEX idx_scenariostep_step_id ON scenario_step(step_id);

-- ============================================================================
-- TABLE: Task
-- Implementation task for a step
-- One task per step (1:1 relationship)
-- ============================================================================
CREATE TABLE task (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    step_id UUID NOT NULL,
    task_name VARCHAR(500) NOT NULL,
    description TEXT NULL,
    implementation_details TEXT NULL, -- Detailed implementation instructions
    code_location VARCHAR(1000) NULL, -- File path where implementation exists
    status VARCHAR(50) NOT NULL DEFAULT 'Pending', -- Pending, InProgress, Completed, Blocked, Failed
    priority INTEGER NOT NULL DEFAULT 0,
    assigned_agent_id UUID NULL, -- Currently assigned agent
    started_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    estimated_minutes INTEGER NULL,
    actual_minutes INTEGER NULL,
    notes TEXT NULL, -- Working notes from agents
    error_log TEXT NULL, -- Any errors encountered during implementation
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_task_step FOREIGN KEY (step_id) REFERENCES step(id),
    CONSTRAINT uq_task_step_id UNIQUE (step_id) -- One task per step
);

CREATE INDEX idx_task_status ON task(status);
CREATE INDEX idx_task_assigned_agent_id ON task(assigned_agent_id);
CREATE INDEX idx_task_priority ON task(priority);

-- ============================================================================
-- TABLE: Agent
-- Tracks autonomous agents working on tasks
-- ============================================================================
CREATE TABLE agent (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_name VARCHAR(255) NOT NULL,
    agent_type VARCHAR(100) NOT NULL, -- e.g., "general-purpose", "Explore", "Plan"
    current_task_id UUID NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'Idle', -- Idle, Working, Completed, Failed, Terminated
    started_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    last_heartbeat TIMESTAMP NULL, -- Track if agent is still alive
    work_log TEXT NULL, -- Detailed log of what the agent accomplished
    result_summary TEXT NULL, -- Summary of results for next agent
    error_message TEXT NULL, -- Error if agent failed
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_agent_status ON agent(status);
CREATE INDEX idx_agent_current_task_id ON agent(current_task_id);

-- ============================================================================
-- TABLE: AgentTaskHistory
-- Historical record of agent task assignments
-- ============================================================================
CREATE TABLE agent_task_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id UUID NOT NULL,
    task_id UUID NOT NULL,
    started_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP NULL,
    status VARCHAR(50) NOT NULL, -- InProgress, Completed, Failed, Abandoned
    work_accomplished TEXT NULL,
    next_steps TEXT NULL, -- Notes for next agent
    files_modified TEXT NULL, -- List of files changed
    build_succeeded BOOLEAN NULL,
    tests_passed BOOLEAN NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_agenttaskhistory_agent FOREIGN KEY (agent_id) REFERENCES agent(id),
    CONSTRAINT fk_agenttaskhistory_task FOREIGN KEY (task_id) REFERENCES task(id)
);

CREATE INDEX idx_agenttaskhistory_agent_id ON agent_task_history(agent_id);
CREATE INDEX idx_agenttaskhistory_task_id ON agent_task_history(task_id);
CREATE INDEX idx_agenttaskhistory_status ON agent_task_history(status);

-- ============================================================================
-- Add foreign keys that reference tables created later
-- ============================================================================
ALTER TABLE task
ADD CONSTRAINT fk_task_agent FOREIGN KEY (assigned_agent_id) REFERENCES agent(id);

ALTER TABLE agent
ADD CONSTRAINT fk_agent_task FOREIGN KEY (current_task_id) REFERENCES task(id);

-- ============================================================================
-- VIEWS FOR COMMON QUERIES
-- ============================================================================

-- View: Complete Feature with all scenarios and steps
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

-- ============================================================================
-- STORED PROCEDURES (PostgreSQL Functions)
-- ============================================================================

-- Function: Assign task to agent
CREATE OR REPLACE FUNCTION sp_assign_task_to_agent(
    p_task_id UUID,
    p_agent_id UUID
) RETURNS VOID AS $$
BEGIN
    -- Update task
    UPDATE task
    SET assigned_agent_id = p_agent_id,
        status = 'InProgress',
        started_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_task_id;

    -- Update agent
    UPDATE agent
    SET current_task_id = p_task_id,
        status = 'Working',
        started_at = CURRENT_TIMESTAMP,
        last_heartbeat = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_agent_id;

    -- Create history record
    INSERT INTO agent_task_history (agent_id, task_id, started_at, status)
    VALUES (p_agent_id, p_task_id, CURRENT_TIMESTAMP, 'InProgress');
END;
$$ LANGUAGE plpgsql;

-- Function: Complete task
CREATE OR REPLACE FUNCTION sp_complete_task(
    p_task_id UUID,
    p_agent_id UUID,
    p_work_accomplished TEXT,
    p_build_succeeded BOOLEAN,
    p_tests_passed BOOLEAN
) RETURNS VOID AS $$
DECLARE
    v_started_at TIMESTAMP;
BEGIN
    -- Get started_at time
    SELECT started_at INTO v_started_at FROM task WHERE id = p_task_id;

    -- Update task
    UPDATE task
    SET status = 'Completed',
        completed_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP,
        actual_minutes = EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_started_at))/60
    WHERE id = p_task_id;

    -- Update agent
    UPDATE agent
    SET status = 'Completed',
        current_task_id = NULL,
        completed_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_agent_id;

    -- Update history
    UPDATE agent_task_history
    SET completed_at = CURRENT_TIMESTAMP,
        status = 'Completed',
        work_accomplished = p_work_accomplished,
        build_succeeded = p_build_succeeded,
        tests_passed = p_tests_passed
    WHERE agent_id = p_agent_id AND task_id = p_task_id AND completed_at IS NULL;
END;
$$ LANGUAGE plpgsql;

-- Function: Get next available task
CREATE OR REPLACE FUNCTION sp_get_next_task(
    p_agent_type VARCHAR DEFAULT NULL
) RETURNS TABLE (
    id UUID,
    step_id UUID,
    task_name VARCHAR,
    description TEXT,
    implementation_details TEXT,
    code_location VARCHAR,
    status VARCHAR,
    priority INTEGER,
    assigned_agent_id UUID,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    estimated_minutes INTEGER,
    actual_minutes INTEGER,
    notes TEXT,
    error_log TEXT,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    step_type VARCHAR,
    step_text VARCHAR,
    scenario_name VARCHAR,
    feature_name VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.id,
        t.step_id,
        t.task_name,
        t.description,
        t.implementation_details,
        t.code_location,
        t.status,
        t.priority,
        t.assigned_agent_id,
        t.started_at,
        t.completed_at,
        t.estimated_minutes,
        t.actual_minutes,
        t.notes,
        t.error_log,
        t.created_at,
        t.updated_at,
        st.step_type,
        st.step_text,
        s.scenario_name,
        f.feature_name
    FROM task t
    INNER JOIN step st ON t.step_id = st.id
    INNER JOIN scenario_step ss ON st.id = ss.step_id
    INNER JOIN scenario s ON ss.scenario_id = s.id
    INNER JOIN feature f ON s.feature_id = f.id
    WHERE t.status = 'Pending'
    AND t.assigned_agent_id IS NULL
    AND f.is_active = TRUE
    ORDER BY t.priority DESC, t.created_at ASC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Confirmation message
SELECT 'Schema created successfully' AS status;
