-- =====================================================
-- StreamSage Enhanced Database Schema - Workflow Engine
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Workflow definitions, rules, and approval tracking
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

CREATE TABLE IF NOT EXISTS streamsage.workflow_definition (
    workflow_id SERIAL PRIMARY KEY,
    workflow_code VARCHAR(50) NOT NULL,
    workflow_name VARCHAR(100) NOT NULL,
    workflow_desc VARCHAR(1000),
    workflow_version INTEGER NOT NULL DEFAULT 1,
    is_active CHAR(1) NOT NULL DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    is_default CHAR(1) NOT NULL DEFAULT 'N' CHECK (is_default IN ('Y','N')),
    workflow_type VARCHAR(50) NOT NULL,
    application_id INTEGER REFERENCES streamsage.apps(application_id),
    tx_type_cd VARCHAR(20),
    workstream_cd VARCHAR(20),
    workflow_config_json JSONB,
    initial_state_cd VARCHAR(20) NOT NULL REFERENCES streamsage.tx_state(tx_state_cd),
    terminal_states VARCHAR(500),
    allowed_roles VARCHAR(1000),
    sla_hours INTEGER,
    escalation_hours INTEGER,
    effective_from_dt DATE NOT NULL,
    effective_to_dt DATE,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I' CHECK (row_status_cd IN ('I','H','D')),
    UNIQUE(workflow_code, workflow_version)
);

CREATE TABLE IF NOT EXISTS streamsage.workflow_transition_rule (
    rule_id SERIAL PRIMARY KEY,
    workflow_id INTEGER NOT NULL REFERENCES streamsage.workflow_definition(workflow_id),
    rule_name VARCHAR(100) NOT NULL,
    from_state_cd VARCHAR(20) REFERENCES streamsage.tx_state(tx_state_cd),
    to_state_cd VARCHAR(20) NOT NULL REFERENCES streamsage.tx_state(tx_state_cd),
    rule_expression VARCHAR(4000),
    rule_type VARCHAR(20) DEFAULT 'CONDITION' CHECK (rule_type IN ('CONDITION','VALIDATION','CALCULATION','NOTIFICATION')),
    rule_order INTEGER NOT NULL DEFAULT 1,
    is_automatic CHAR(1) NOT NULL DEFAULT 'N' CHECK (is_automatic IN ('Y','N')),
    auto_trigger_event VARCHAR(50),
    required_role VARCHAR(100),
    required_permission VARCHAR(100),
    approval_required CHAR(1) DEFAULT 'N' CHECK (approval_required IN ('Y','N')),
    approver_role VARCHAR(100),
    min_approvers INTEGER DEFAULT 1,
    notification_template_id INTEGER,
    pre_action_script TEXT,
    post_action_script TEXT,
    error_message VARCHAR(500),
    is_active CHAR(1) NOT NULL DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I' CHECK (row_status_cd IN ('I','H','D'))
);

CREATE TABLE IF NOT EXISTS streamsage.business_rule (
    rule_id SERIAL PRIMARY KEY,
    rule_code VARCHAR(50) NOT NULL UNIQUE,
    rule_name VARCHAR(100) NOT NULL,
    rule_desc VARCHAR(1000),
    rule_type VARCHAR(20) NOT NULL CHECK (rule_type IN ('VALIDATION','CALCULATION','NOTIFICATION','TRANSFORMATION','AUTHORIZATION')),
    rule_category VARCHAR(50),
    rule_expression TEXT NOT NULL,
    rule_language VARCHAR(20) DEFAULT 'SQL' CHECK (rule_language IN ('SQL','JAVASCRIPT','PYTHON','GROOVY','JSON')),
    error_message VARCHAR(500),
    severity VARCHAR(20) NOT NULL DEFAULT 'ERROR' CHECK (severity IN ('INFO','WARNING','ERROR','CRITICAL')),
    is_active CHAR(1) NOT NULL DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    is_blocking CHAR(1) NOT NULL DEFAULT 'Y' CHECK (is_blocking IN ('Y','N')),
    execution_order INTEGER NOT NULL DEFAULT 100,
    application_id INTEGER REFERENCES streamsage.apps(application_id),
    tx_type_cd VARCHAR(20),
    workstream_cd VARCHAR(20),
    trigger_event VARCHAR(50),
    effective_from_dt DATE NOT NULL,
    effective_to_dt DATE,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I' CHECK (row_status_cd IN ('I','H','D'))
);

CREATE TABLE IF NOT EXISTS streamsage.tx_approval_workflow (
    approval_wf_uid BIGSERIAL PRIMARY KEY,
    tx_uid BIGINT NOT NULL REFERENCES streamsage.hub_transaction(tx_uid) ON DELETE CASCADE,
    approval_level INTEGER NOT NULL DEFAULT 1,
    approver_user_cnum VARCHAR(10) NOT NULL,
    approver_role VARCHAR(100),
    approval_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (approval_status IN ('PENDING','IN_PROGRESS','APPROVED','REJECTED','DELEGATED','EXPIRED','CANCELLED')),
    approval_decision VARCHAR(20) CHECK (approval_decision IN ('APPROVE','REJECT','ABSTAIN')),
    approval_comment VARCHAR(2000),
    requested_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    responded_ts TIMESTAMP,
    due_ts TIMESTAMP,
    reminder_sent_count INTEGER DEFAULT 0,
    last_reminder_ts TIMESTAMP,
    delegation_to_user VARCHAR(10),
    delegation_reason VARCHAR(500),
    is_mandatory CHAR(1) DEFAULT 'Y' CHECK (is_mandatory IN ('Y','N')),
    sequence_order INTEGER NOT NULL DEFAULT 1,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I' CHECK (row_status_cd IN ('I','H','D'))
);

CREATE INDEX IF NOT EXISTS idx_tx_approval_tx ON streamsage.tx_approval_workflow(tx_uid, approval_level);
CREATE INDEX IF NOT EXISTS idx_tx_approval_user ON streamsage.tx_approval_workflow(approver_user_cnum, approval_status);
