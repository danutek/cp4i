-- =====================================================
-- StreamSage Enhanced Database Schema - Family Rules
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Configurable rules for automatic family assignment
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- TRANSACTION FAMILY RULE TABLE
-- Purpose: Defines rules for automatically assigning transactions to families
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_family_rule (
    tx_family_rule_uid BIGSERIAL,
    application_id INTEGER NOT NULL
        REFERENCES streamsage.apps(application_id),
    tx_type_cd VARCHAR(20),
    workstream_cd VARCHAR(20),
    workflow_type_cd VARCHAR(20),
    family_type_cd VARCHAR(30) NOT NULL,
    matching_strategy_cd VARCHAR(30) NOT NULL,
    attribute_code VARCHAR(150),
    parent_workstream_cd VARCHAR(20),
    parent_workflow_type_cd VARCHAR(20),
    parent_attribute_code VARCHAR(150),
    create_new_family_indc CHAR(1) NOT NULL DEFAULT 'N',
    inherit_parent_family_indc CHAR(1) NOT NULL DEFAULT 'N',
    allow_manual_override_indc CHAR(1) NOT NULL DEFAULT 'Y',
    priority_num INTEGER NOT NULL DEFAULT 100,
    effective_from_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to_ts TIMESTAMP,
    active_indc CHAR(1) NOT NULL DEFAULT 'Y',
    create_id VARCHAR(60) NOT NULL,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(60) NOT NULL,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT pk_tx_family_rule PRIMARY KEY (tx_family_rule_uid),
    CONSTRAINT fk_tx_family_rule_app FOREIGN KEY (application_id) REFERENCES streamsage.apps (application_id),
    CONSTRAINT chk_tx_family_rule_status CHECK (row_status_cd IN ('A', 'I', 'D')),
    CONSTRAINT chk_tx_family_rule_create_new CHECK (create_new_family_indc IN ('Y', 'N')),
    CONSTRAINT chk_tx_family_rule_inherit CHECK (inherit_parent_family_indc IN ('Y', 'N')),
    CONSTRAINT chk_tx_family_rule_override CHECK (allow_manual_override_indc IN ('Y', 'N')),
    CONSTRAINT chk_tx_family_rule_active CHECK (active_indc IN ('Y', 'N')),
    CONSTRAINT chk_tx_family_rule_effective CHECK (effective_to_ts IS NULL OR effective_to_ts >= effective_from_ts)
);

CREATE INDEX IF NOT EXISTS idx_tx_family_rule_app ON streamsage.tx_family_rule (application_id, active_indc);
CREATE INDEX IF NOT EXISTS idx_tx_family_rule_type ON streamsage.tx_family_rule (tx_type_cd, workstream_cd, workflow_type_cd);
CREATE INDEX IF NOT EXISTS idx_tx_family_rule_priority ON streamsage.tx_family_rule (priority_num, active_indc);
CREATE INDEX IF NOT EXISTS idx_tx_family_rule_effective ON streamsage.tx_family_rule (effective_from_ts, effective_to_ts);

COMMENT ON TABLE streamsage.tx_family_rule IS 'Configurable rules for automatically assigning transactions to families based on matching strategies';
COMMENT ON COLUMN streamsage.tx_family_rule.matching_strategy_cd IS 'Strategy for matching transactions (e.g., ATTRIBUTE_MATCH, PARENT_CHILD, BUSINESS_KEY)';
COMMENT ON COLUMN streamsage.tx_family_rule.attribute_code IS 'Attribute to use for matching when using ATTRIBUTE_MATCH strategy';
COMMENT ON COLUMN streamsage.tx_family_rule.create_new_family_indc IS 'Whether to create a new family if no match is found';
COMMENT ON COLUMN streamsage.tx_family_rule.inherit_parent_family_indc IS 'Whether to inherit family from parent transaction';
COMMENT ON COLUMN streamsage.tx_family_rule.priority_num IS 'Rule execution priority (lower numbers execute first)';

-- Apply update timestamp trigger
CREATE OR REPLACE TRIGGER trg_tx_family_rule_update_ts BEFORE UPDATE ON streamsage.tx_family_rule
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();