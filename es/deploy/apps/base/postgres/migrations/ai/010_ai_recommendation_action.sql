-- =====================================================
-- StreamSage Enhanced Database Schema - AI Recommendation Actions
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Granular action steps for AI recommendations
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- AI RECOMMENDATION ACTION TABLE
-- Purpose: Breaks down recommendations into executable action steps with policy controls
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.ai_recommendation_action (
    ai_recommendation_action_uid  BIGSERIAL PRIMARY KEY,
    ai_recommendation_uid         BIGINT NOT NULL REFERENCES streamsage.ai_recommendation(ai_recommendation_uid),
    action_sequence_num           INTEGER NOT NULL DEFAULT 1,
    action_type_cd                VARCHAR(60) NOT NULL,
    action_status_cd              VARCHAR(20) NOT NULL DEFAULT 'PROPOSED',
    action_summary_txt            VARCHAR(1000),
    action_request_json           JSONB NOT NULL,
    confidence_score_num          NUMERIC(5,4),
    execution_priority_cd         VARCHAR(20) NOT NULL DEFAULT 'NORMAL',
    policy_decision_cd            VARCHAR(20),
    requires_human_review_indc    CHAR(1) NOT NULL DEFAULT 'Y',
    create_id                     VARCHAR(60) NOT NULL,
    create_ts                     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id                     VARCHAR(60) NOT NULL,
    update_ts                     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd                 CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT chk_aira_status CHECK (
        action_status_cd IN ('PROPOSED','APPROVED','REJECTED','QUEUED','EXECUTED','FAILED','SKIPPED')
    ),
    CONSTRAINT chk_aira_priority CHECK (
        execution_priority_cd IN ('LOW','NORMAL','HIGH','URGENT')
    ),
    CONSTRAINT chk_aira_policy CHECK (
        policy_decision_cd IS NULL OR policy_decision_cd IN ('ALLOW','DRAFT_ONLY','REVIEW_REQUIRED','DENY')
    ),
    CONSTRAINT chk_aira_review CHECK (requires_human_review_indc IN ('Y','N')),
    CONSTRAINT chk_aira_row_status CHECK (row_status_cd IN ('A','I','D')),
    CONSTRAINT chk_aira_confidence CHECK (
        confidence_score_num IS NULL OR (confidence_score_num >= 0 AND confidence_score_num <= 1)
    ),
    CONSTRAINT chk_aira_sequence CHECK (action_sequence_num >= 1)
);

CREATE INDEX IF NOT EXISTS idx_ai_rec_action_rec ON streamsage.ai_recommendation_action (ai_recommendation_uid, action_sequence_num);
CREATE INDEX IF NOT EXISTS idx_ai_rec_action_status ON streamsage.ai_recommendation_action (action_status_cd, execution_priority_cd, create_ts);
CREATE INDEX IF NOT EXISTS idx_ai_rec_action_type ON streamsage.ai_recommendation_action (action_type_cd, action_status_cd);
CREATE INDEX IF NOT EXISTS idx_ai_rec_action_policy ON streamsage.ai_recommendation_action (policy_decision_cd, requires_human_review_indc);

COMMENT ON TABLE streamsage.ai_recommendation_action IS 'Granular action steps that comprise a recommendation, with individual approval and execution tracking';
COMMENT ON COLUMN streamsage.ai_recommendation_action.action_type_cd IS 'Specific action type (e.g., UPDATE_FIELD, ADD_COMMENT, CHANGE_STATE, ASSIGN_USER, CREATE_TASK)';
COMMENT ON COLUMN streamsage.ai_recommendation_action.action_status_cd IS 'Status: PROPOSED, APPROVED, REJECTED, QUEUED, EXECUTED, FAILED, SKIPPED';
COMMENT ON COLUMN streamsage.ai_recommendation_action.action_request_json IS 'Detailed action parameters and data for execution';
COMMENT ON COLUMN streamsage.ai_recommendation_action.policy_decision_cd IS 'Policy engine decision: ALLOW, DRAFT_ONLY, REVIEW_REQUIRED, DENY';
COMMENT ON COLUMN streamsage.ai_recommendation_action.action_sequence_num IS 'Execution order within the recommendation';

-- Apply update timestamp trigger
CREATE OR REPLACE TRIGGER trg_ai_rec_action_update_ts BEFORE UPDATE ON streamsage.ai_recommendation_action
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();