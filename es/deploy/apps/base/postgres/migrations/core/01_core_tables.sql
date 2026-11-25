-- =====================================================
-- StreamSage Enhanced Database Schema - Core Tables
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Core transaction and application tables
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

-- Create schema
CREATE SCHEMA IF NOT EXISTS streamsage;

SET search_path TO streamsage;

-- =====================================================
-- APPLICATIONS TABLE (Enhanced)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.apps (
    application_id INTEGER NOT NULL,
    application_code VARCHAR(20) NOT NULL,
    application_name VARCHAR(72) NOT NULL,
    application_system_id INTEGER NOT NULL,
    app_opfolder_id VARCHAR(64),
    app_opfolder_nm VARCHAR(154),
    is_active CHAR(1) NOT NULL DEFAULT 'Y',
    config_json JSONB,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_apps PRIMARY KEY (application_id),
    CONSTRAINT uk_apps_code UNIQUE (application_code),
    CONSTRAINT chk_apps_status CHECK (row_status_cd IN ('A', 'I', 'D')),
    CONSTRAINT chk_apps_active CHECK (is_active IN ('Y', 'N'))
);

CREATE INDEX IF NOT EXISTS idx_apps_code ON streamsage.apps (application_code);
CREATE INDEX IF NOT EXISTS idx_apps_active ON streamsage.apps (is_active, row_status_cd);

COMMENT ON TABLE streamsage.apps IS 'Application registry with enhanced configuration support';

-- =====================================================
-- TRANSACTION STATES TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_state (
    tx_state_cd VARCHAR(20) NOT NULL,
    tx_state_nm VARCHAR(100) NOT NULL,
    tx_state_desc VARCHAR(500),
    is_terminal_state CHAR(1) NOT NULL DEFAULT 'N',
    display_order INTEGER,
    state_color VARCHAR(20),
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_tx_state PRIMARY KEY (tx_state_cd),
    CONSTRAINT chk_tx_state_status CHECK (row_status_cd IN ('I', 'H', 'D')),
    CONSTRAINT chk_tx_state_terminal CHECK (is_terminal_state IN ('Y', 'N'))
);

CREATE INDEX IF NOT EXISTS idx_tx_state_order ON streamsage.tx_state (display_order);

COMMENT ON TABLE streamsage.tx_state IS 'Transaction state definitions for workflow management';

-- =====================================================
-- HUB TRANSACTION TABLE (Enhanced)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.hub_transaction (
    tx_uid BIGSERIAL NOT NULL,
    op_tx_line_uid VARCHAR(50) NOT NULL,
    tx_revision_num INTEGER NOT NULL DEFAULT 1,
    tx_nm VARCHAR(200),
    tx_desc VARCHAR(1000),
    linked_version_indc CHAR(1) DEFAULT 'N',
    revision_num INTEGER DEFAULT 1,
    reference_tx_id VARCHAR(50),
    tx_type_cd VARCHAR(20) NOT NULL,
    tx_state_cd VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
    oppty_num VARCHAR(50),
    account_num VARCHAR(50),
    lead_ctry_cd VARCHAR(10),
    lob_id INTEGER,
    offering_id INTEGER,
    application_id INTEGER NOT NULL,
    app_versionbuild_txt VARCHAR(50),
    workstream_cd VARCHAR(20) NOT NULL,
    workflow_type_cd VARCHAR(20) NOT NULL,
    parent_tx_uid BIGINT,
    parent_op_uid VARCHAR(50),
    tx_line_generate_indc CHAR(1) DEFAULT 'N',
    version_num INTEGER NOT NULL DEFAULT 1,
    lock_version INTEGER NOT NULL DEFAULT 0,
    locked_by_user VARCHAR(10),
    locked_ts TIMESTAMP,
    priority_level INTEGER DEFAULT 3,
    due_date DATE,
    completion_date DATE,
    estimated_value DECIMAL(20,4),
    actual_value DECIMAL(20,4),
    currency_cd VARCHAR(3),
    tags VARCHAR(500),
    external_ref_id VARCHAR(100),
    external_system_cd VARCHAR(50),
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_hub_transaction PRIMARY KEY (tx_uid),
    CONSTRAINT fk_tx_app FOREIGN KEY (application_id) REFERENCES streamsage.apps (application_id),
    CONSTRAINT fk_tx_state FOREIGN KEY (tx_state_cd) REFERENCES streamsage.tx_state (tx_state_cd),
    CONSTRAINT fk_tx_parent FOREIGN KEY (parent_tx_uid) REFERENCES streamsage.hub_transaction (tx_uid),
    CONSTRAINT chk_tx_status CHECK (row_status_cd IN ('I', 'H', 'D')),
    CONSTRAINT chk_tx_linked CHECK (linked_version_indc IN ('Y', 'N')),
    CONSTRAINT chk_tx_dna_gen CHECK (tx_line_generate_indc IN ('Y', 'N')),
    CONSTRAINT chk_tx_priority CHECK (priority_level BETWEEN 1 AND 5)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_tx_op_tx_line ON streamsage.hub_transaction (op_tx_line_uid, row_status_cd);
CREATE INDEX IF NOT EXISTS idx_tx_type_workstream ON streamsage.hub_transaction (tx_type_cd, workstream_cd, workflow_type_cd);
CREATE INDEX IF NOT EXISTS idx_tx_app_create ON streamsage.hub_transaction (application_id, create_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_state ON streamsage.hub_transaction (tx_state_cd, row_status_cd);
CREATE INDEX IF NOT EXISTS idx_tx_parent ON streamsage.hub_transaction (parent_tx_uid);
CREATE INDEX IF NOT EXISTS idx_tx_create_user ON streamsage.hub_transaction (create_id, create_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_external_ref ON streamsage.hub_transaction (external_ref_id, external_system_cd);
CREATE INDEX IF NOT EXISTS idx_tx_due_date ON streamsage.hub_transaction (due_date) WHERE due_date IS NOT NULL;

COMMENT ON TABLE streamsage.hub_transaction IS 'Enhanced transaction hub with state management and flexible attributes';

-- =====================================================
-- TRANSACTION HIERARCHY TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_hierarchy (
    tx_uid BIGINT NOT NULL,
    ancestor_tx_uid BIGINT NOT NULL,
    depth_level INTEGER NOT NULL,
    path_string VARCHAR(1000),
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_tx_hierarchy PRIMARY KEY (tx_uid, ancestor_tx_uid),
    CONSTRAINT fk_tx_hier_tx FOREIGN KEY (tx_uid) REFERENCES streamsage.hub_transaction (tx_uid),
    CONSTRAINT fk_tx_hier_ancestor FOREIGN KEY (ancestor_tx_uid) REFERENCES streamsage.hub_transaction (tx_uid)
);

CREATE INDEX IF NOT EXISTS idx_tx_hier_ancestor ON streamsage.tx_hierarchy (ancestor_tx_uid, depth_level);
CREATE INDEX IF NOT EXISTS idx_tx_hier_depth ON streamsage.tx_hierarchy (depth_level);

COMMENT ON TABLE streamsage.tx_hierarchy IS 'Materialized path for efficient hierarchy queries';

-- =====================================================
-- TRANSACTION STATE HISTORY TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_state_history (
    tx_state_hist_uid BIGSERIAL NOT NULL,
    tx_uid BIGINT NOT NULL,
    from_state_cd VARCHAR(20),
    to_state_cd VARCHAR(20) NOT NULL,
    transition_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    transition_user_id VARCHAR(10) NOT NULL,
    transition_reason VARCHAR(500),
    transition_comment VARCHAR(2000),
    ip_address VARCHAR(45),
    session_id VARCHAR(100),
    duration_seconds INTEGER,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_tx_state_hist PRIMARY KEY (tx_state_hist_uid),
    CONSTRAINT fk_tx_state_hist_tx FOREIGN KEY (tx_uid) REFERENCES streamsage.hub_transaction (tx_uid),
    CONSTRAINT fk_tx_state_hist_from FOREIGN KEY (from_state_cd) REFERENCES streamsage.tx_state (tx_state_cd),
    CONSTRAINT fk_tx_state_hist_to FOREIGN KEY (to_state_cd) REFERENCES streamsage.tx_state (tx_state_cd),
    CONSTRAINT chk_tx_state_hist_status CHECK (row_status_cd IN ('I', 'H', 'D'))
);

CREATE INDEX IF NOT EXISTS idx_tx_state_hist_tx ON streamsage.tx_state_history (tx_uid, transition_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_state_hist_user ON streamsage.tx_state_history (transition_user_id, transition_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_state_hist_state ON streamsage.tx_state_history (to_state_cd, transition_ts DESC);

COMMENT ON TABLE streamsage.tx_state_history IS 'Complete history of transaction state transitions';

-- Create update timestamp trigger function
CREATE OR REPLACE FUNCTION streamsage.update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.update_ts = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update timestamp triggers
CREATE OR REPLACE TRIGGER trg_apps_update_ts BEFORE UPDATE ON streamsage.apps
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();

CREATE OR REPLACE TRIGGER trg_tx_state_update_ts BEFORE UPDATE ON streamsage.tx_state
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();

CREATE OR REPLACE TRIGGER trg_hub_transaction_update_ts BEFORE UPDATE ON streamsage.hub_transaction
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();

