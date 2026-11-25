-- =====================================================
-- StreamSage Enhanced Database Schema - AI Observations
-- Version: 2.0
-- Database: PostgreSQL
-- Description: AI-generated insights and observations
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- AI OBSERVATION TABLE
-- Purpose: Stores AI-generated insights, patterns, and observations about transactions
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.ai_observation (
    ai_observation_uid           BIGSERIAL PRIMARY KEY,
    ai_analysis_request_uid      BIGINT NOT NULL REFERENCES streamsage.ai_analysis_request(ai_analysis_request_uid),
    tx_uid                       BIGINT REFERENCES streamsage.hub_transaction(tx_uid),
    tx_family_uid                BIGINT REFERENCES streamsage.tx_family(tx_family_uid),
    observation_type_cd          VARCHAR(60) NOT NULL,
    observation_status_cd        VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    summary_txt                  TEXT NOT NULL,
    details_json                 JSONB,
    confidence_score_num         NUMERIC(5,4),
    risk_level_cd                VARCHAR(20),
    ai_model_uid                 BIGINT REFERENCES streamsage.ai_model_registry(ai_model_uid),
    ai_prompt_template_uid       BIGINT REFERENCES streamsage.ai_prompt_template(ai_prompt_template_uid),
    ai_context_snapshot_uid      BIGINT REFERENCES streamsage.ai_context_snapshot(ai_context_snapshot_uid),
    superseded_by_uid            BIGINT REFERENCES streamsage.ai_observation(ai_observation_uid),
    create_id                    VARCHAR(60) NOT NULL,
    create_ts                    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expire_ts                    TIMESTAMP,
    row_status_cd                CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT chk_aio_status CHECK (
        observation_status_cd IN ('ACTIVE','SUPERSEDED','EXPIRED','WITHDRAWN')
    ),
    CONSTRAINT chk_aio_risk CHECK (
        risk_level_cd IS NULL OR risk_level_cd IN ('LOW','MEDIUM','HIGH','CRITICAL')
    ),
    CONSTRAINT chk_aio_row_status CHECK (row_status_cd IN ('A','I','D')),
    CONSTRAINT chk_aio_confidence CHECK (
        confidence_score_num IS NULL OR (confidence_score_num >= 0 AND confidence_score_num <= 1)
    )
);

CREATE INDEX IF NOT EXISTS idx_ai_observation_request ON streamsage.ai_observation (ai_analysis_request_uid, create_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_observation_tx ON streamsage.ai_observation (tx_uid, observation_status_cd);
CREATE INDEX IF NOT EXISTS idx_ai_observation_family ON streamsage.ai_observation (tx_family_uid, observation_status_cd);
CREATE INDEX IF NOT EXISTS idx_ai_observation_type ON streamsage.ai_observation (observation_type_cd, observation_status_cd, create_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_observation_risk ON streamsage.ai_observation (risk_level_cd, observation_status_cd) WHERE risk_level_cd IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ai_observation_superseded ON streamsage.ai_observation (superseded_by_uid) WHERE superseded_by_uid IS NOT NULL;

COMMENT ON TABLE streamsage.ai_observation IS 'AI-generated insights, patterns, and observations about transactions with confidence scoring';
COMMENT ON COLUMN streamsage.ai_observation.observation_type_cd IS 'Type of observation (e.g., ANOMALY, PATTERN, RISK, OPPORTUNITY, COMPLIANCE_ISSUE, DATA_QUALITY)';
COMMENT ON COLUMN streamsage.ai_observation.observation_status_cd IS 'Status: ACTIVE (current), SUPERSEDED (replaced by newer), EXPIRED (time-limited), WITHDRAWN (retracted)';
COMMENT ON COLUMN streamsage.ai_observation.confidence_score_num IS 'AI confidence in the observation (0.0 to 1.0)';
COMMENT ON COLUMN streamsage.ai_observation.risk_level_cd IS 'Risk assessment: LOW, MEDIUM, HIGH, CRITICAL';
COMMENT ON COLUMN streamsage.ai_observation.superseded_by_uid IS 'Reference to newer observation that replaces this one';