-- =====================================================
-- StreamSage Enhanced Database Schema - AI Recommendations
-- Version: 2.0
-- Database: PostgreSQL
-- Description: AI-generated actionable recommendations
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- AI RECOMMENDATION TABLE
-- Purpose: Stores AI-generated actionable recommendations with approval workflow
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.ai_recommendation (
    ai_recommendation_uid         BIGSERIAL PRIMARY KEY,
    ai_analysis_request_uid       BIGINT NOT NULL REFERENCES streamsage.ai_analysis_request(ai_analysis_request_uid),
    tx_uid                        BIGINT REFERENCES streamsage.hub_transaction(tx_uid),
    tx_family_uid                 BIGINT REFERENCES streamsage.tx_family(tx_family_uid),
    recommendation_type_cd        VARCHAR(60) NOT NULL,
    recommendation_status_cd      VARCHAR(20) NOT NULL DEFAULT 'NEW',
    summary_txt                   TEXT NOT NULL,
    recommendation_json           JSONB NOT NULL,
    confidence_score_num          NUMERIC(5,4),
    risk_level_cd                 VARCHAR(20),
    requires_human_review_indc    CHAR(1) NOT NULL DEFAULT 'Y',
    recommended_by_actor_type_cd  VARCHAR(20) NOT NULL DEFAULT 'SYSTEM',
    recommended_by_actor_id       VARCHAR(100) NOT NULL,
    ai_model_uid                  BIGINT REFERENCES streamsage.ai_model_registry(ai_model_uid),
    ai_prompt_template_uid        BIGINT REFERENCES streamsage.ai_prompt_template(ai_prompt_template_uid),
    ai_context_snapshot_uid       BIGINT REFERENCES streamsage.ai_context_snapshot(ai_context_snapshot_uid),
    parent_ai_recommendation_uid  BIGINT REFERENCES streamsage.ai_recommendation(ai_recommendation_uid),
    create_id                     VARCHAR(60) NOT NULL,
    create_ts                     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expire_ts                     TIMESTAMP,
    row_status_cd                 CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT chk_air_status CHECK (
        recommendation_status_cd IN (
            'NEW','PENDING_REVIEW','ACCEPTED','REJECTED','EXPIRED','EXECUTED','FAILED','WITHDRAWN'
        )
    ),
    CONSTRAINT chk_air_review CHECK (requires_human_review_indc IN ('Y','N')),
    CONSTRAINT chk_air_actor_type CHECK (
        recommended_by_actor_type_cd IN ('USER','SYSTEM','SERVICE','BATCH')
    ),
    CONSTRAINT chk_air_risk CHECK (
        risk_level_cd IS NULL OR risk_level_cd IN ('LOW','MEDIUM','HIGH','CRITICAL')
    ),
    CONSTRAINT chk_air_row_status CHECK (row_status_cd IN ('A','I','D')),
    CONSTRAINT chk_air_confidence CHECK (
        confidence_score_num IS NULL OR (confidence_score_num >= 0 AND confidence_score_num <= 1)
    )
);

CREATE INDEX IF NOT EXISTS idx_ai_recommendation_request ON streamsage.ai_recommendation (ai_analysis_request_uid, create_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_recommendation_tx ON streamsage.ai_recommendation (tx_uid, recommendation_status_cd);
CREATE INDEX IF NOT EXISTS idx_ai_recommendation_family ON streamsage.ai_recommendation (tx_family_uid, recommendation_status_cd);
CREATE INDEX IF NOT EXISTS idx_ai_recommendation_type ON streamsage.ai_recommendation (recommendation_type_cd, recommendation_status_cd, create_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_recommendation_status ON streamsage.ai_recommendation (recommendation_status_cd, create_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_recommendation_review ON streamsage.ai_recommendation (requires_human_review_indc, recommendation_status_cd) WHERE requires_human_review_indc = 'Y';
CREATE INDEX IF NOT EXISTS idx_ai_recommendation_parent ON streamsage.ai_recommendation (parent_ai_recommendation_uid);

COMMENT ON TABLE streamsage.ai_recommendation IS 'AI-generated actionable recommendations with approval workflow and execution tracking';
COMMENT ON COLUMN streamsage.ai_recommendation.recommendation_type_cd IS 'Type of recommendation (e.g., CREATE_TX, UPDATE_TX, APPROVE_TX, ASSIGN_USER, ESCALATE, CLOSE_TX, ADD_COMMENT)';
COMMENT ON COLUMN streamsage.ai_recommendation.recommendation_status_cd IS 'Status: NEW, PENDING_REVIEW, ACCEPTED, REJECTED, EXPIRED, EXECUTED, FAILED, WITHDRAWN';
COMMENT ON COLUMN streamsage.ai_recommendation.recommendation_json IS 'Detailed recommendation data including proposed changes and rationale';
COMMENT ON COLUMN streamsage.ai_recommendation.requires_human_review_indc IS 'Whether human review is required before execution';
COMMENT ON COLUMN streamsage.ai_recommendation.parent_ai_recommendation_uid IS 'Reference to parent recommendation for hierarchical recommendations';

-- Apply update timestamp trigger
CREATE OR REPLACE TRIGGER trg_ai_recommendation_update_ts BEFORE UPDATE ON streamsage.ai_recommendation
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();