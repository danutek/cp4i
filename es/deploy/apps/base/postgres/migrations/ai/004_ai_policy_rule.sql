-- =====================================================
-- StreamSage Enhanced Database Schema - AI Policy Rules
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Governance rules for AI-generated actions and recommendations
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- AI POLICY RULE TABLE
-- Purpose: Defines governance policies for AI actions based on confidence, risk, and context
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.ai_policy_rule (
    ai_policy_rule_uid          BIGSERIAL PRIMARY KEY,
    policy_rule_name            VARCHAR(120) NOT NULL,
    action_type_cd              VARCHAR(60) NOT NULL,
    recommendation_type_cd      VARCHAR(60),
    application_id              INTEGER REFERENCES streamsage.apps(application_id),
    tx_type_cd                  VARCHAR(30),
    family_type_cd              VARCHAR(30),
    workflow_type_cd            VARCHAR(30),
    minimum_confidence_num      NUMERIC(5,4),
    risk_level_cd               VARCHAR(20),
    decision_cd                 VARCHAR(20) NOT NULL,
    requires_human_review_indc  CHAR(1) NOT NULL DEFAULT 'Y',
    active_indc                 CHAR(1) NOT NULL DEFAULT 'Y',
    priority_num                INTEGER NOT NULL DEFAULT 100,
    rule_expression_txt         TEXT,
    effective_from_ts           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to_ts             TIMESTAMP,
    create_id                   VARCHAR(60) NOT NULL,
    create_ts                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id                   VARCHAR(60) NOT NULL,
    update_ts                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd               CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT chk_aipr_decision CHECK (decision_cd IN ('ALLOW','DRAFT_ONLY','REVIEW_REQUIRED','DENY')),
    CONSTRAINT chk_aipr_review CHECK (requires_human_review_indc IN ('Y','N')),
    CONSTRAINT chk_aipr_active CHECK (active_indc IN ('Y','N')),
    CONSTRAINT chk_aipr_row_status CHECK (row_status_cd IN ('A','I','D')),
    CONSTRAINT chk_aipr_effective_ts CHECK (
        effective_to_ts IS NULL OR effective_to_ts >= effective_from_ts
    )
);

CREATE INDEX IF NOT EXISTS idx_ai_policy_action ON streamsage.ai_policy_rule (action_type_cd, active_indc);
CREATE INDEX IF NOT EXISTS idx_ai_policy_app ON streamsage.ai_policy_rule (application_id, tx_type_cd, active_indc);
CREATE INDEX IF NOT EXISTS idx_ai_policy_priority ON streamsage.ai_policy_rule (priority_num, active_indc);
CREATE INDEX IF NOT EXISTS idx_ai_policy_effective ON streamsage.ai_policy_rule (effective_from_ts, effective_to_ts);

COMMENT ON TABLE streamsage.ai_policy_rule IS 'Governance policies that control AI action execution based on confidence scores, risk levels, and business context';
COMMENT ON COLUMN streamsage.ai_policy_rule.action_type_cd IS 'Type of AI action this policy applies to (e.g., CREATE_TX, UPDATE_TX, APPROVE_TX, ASSIGN_USER)';
COMMENT ON COLUMN streamsage.ai_policy_rule.minimum_confidence_num IS 'Minimum confidence score required (0.0 to 1.0)';
COMMENT ON COLUMN streamsage.ai_policy_rule.decision_cd IS 'Policy decision: ALLOW (auto-execute), DRAFT_ONLY (create draft), REVIEW_REQUIRED (human review), DENY (block)';
COMMENT ON COLUMN streamsage.ai_policy_rule.requires_human_review_indc IS 'Whether human review is mandatory regardless of confidence';
COMMENT ON COLUMN streamsage.ai_policy_rule.rule_expression_txt IS 'Additional rule logic in SQL or expression language';

-- Apply update timestamp trigger
CREATE OR REPLACE TRIGGER trg_ai_policy_rule_update_ts BEFORE UPDATE ON streamsage.ai_policy_rule
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();