-- =====================================================
-- StreamSage Enhanced Database Schema - AI Analysis Requests
-- Version: 2.0
-- Database: PostgreSQL
-- Description: AI analysis request tracking and orchestration
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- AI ANALYSIS REQUEST TABLE
-- Purpose: Tracks AI analysis requests from initiation through completion
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.ai_analysis_request (
    ai_analysis_request_uid     BIGSERIAL PRIMARY KEY,
    request_type_cd             VARCHAR(40) NOT NULL,
    request_source_cd           VARCHAR(40) NOT NULL,
    trigger_event_id            VARCHAR(100),
    trigger_event_type_cd       VARCHAR(100),
    application_id              INTEGER REFERENCES streamsage.apps(application_id),
    tx_uid                      BIGINT REFERENCES streamsage.hub_transaction(tx_uid),
    tx_family_uid               BIGINT REFERENCES streamsage.tx_family(tx_family_uid),
    workflow_id                 INTEGER REFERENCES streamsage.workflow_definition(workflow_id),
    ai_prompt_template_uid      BIGINT REFERENCES streamsage.ai_prompt_template(ai_prompt_template_uid),
    ai_model_uid                BIGINT REFERENCES streamsage.ai_model_registry(ai_model_uid),
    request_context_json        JSONB,
    request_priority_cd         VARCHAR(20) NOT NULL DEFAULT 'NORMAL',
    status_cd                   VARCHAR(20) NOT NULL DEFAULT 'NEW',
    requested_by_actor_type_cd  VARCHAR(20) NOT NULL,
    requested_by_actor_id       VARCHAR(100) NOT NULL,
    requested_ts                TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_ts                  TIMESTAMP,
    completed_ts                TIMESTAMP,
    error_txt                   VARCHAR(4000),
    create_id                   VARCHAR(60) NOT NULL,
    create_ts                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id                   VARCHAR(60) NOT NULL,
    update_ts                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd               CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT chk_aiar_req_type CHECK (
        request_type_cd IN ('OBSERVATION','RECOMMENDATION','SUMMARY','TRIAGE','COPILOT','BATCH_SCAN')
    ),
    CONSTRAINT chk_aiar_req_source CHECK (
        request_source_cd IN ('EVENT','USER','SCHEDULED','API','SYSTEM')
    ),
    CONSTRAINT chk_aiar_priority CHECK (
        request_priority_cd IN ('LOW','NORMAL','HIGH','URGENT')
    ),
    CONSTRAINT chk_aiar_status CHECK (
        status_cd IN ('NEW','QUEUED','RUNNING','COMPLETED','FAILED','CANCELLED','SKIPPED')
    ),
    CONSTRAINT chk_aiar_actor_type CHECK (
        requested_by_actor_type_cd IN ('USER','SYSTEM','SERVICE','BATCH')
    ),
    CONSTRAINT chk_aiar_row_status CHECK (row_status_cd IN ('A','I','D')),
    CONSTRAINT chk_aiar_time_order CHECK (
        (started_ts IS NULL OR started_ts >= requested_ts) AND
        (completed_ts IS NULL OR started_ts IS NULL OR completed_ts >= started_ts)
    )
);

CREATE INDEX IF NOT EXISTS idx_ai_analysis_req_status ON streamsage.ai_analysis_request (status_cd, request_priority_cd, requested_ts);
CREATE INDEX IF NOT EXISTS idx_ai_analysis_req_tx ON streamsage.ai_analysis_request (tx_uid, requested_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_analysis_req_family ON streamsage.ai_analysis_request (tx_family_uid, requested_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_analysis_req_type ON streamsage.ai_analysis_request (request_type_cd, status_cd);
CREATE INDEX IF NOT EXISTS idx_ai_analysis_req_trigger ON streamsage.ai_analysis_request (trigger_event_id, trigger_event_type_cd);

COMMENT ON TABLE streamsage.ai_analysis_request IS 'Tracks AI analysis requests from initiation through completion with full lifecycle management';
COMMENT ON COLUMN streamsage.ai_analysis_request.request_type_cd IS 'Type of analysis: OBSERVATION (insights), RECOMMENDATION (actions), SUMMARY (digest), TRIAGE (prioritization), COPILOT (interactive), BATCH_SCAN (bulk)';
COMMENT ON COLUMN streamsage.ai_analysis_request.request_source_cd IS 'Source of request: EVENT (triggered), USER (manual), SCHEDULED (cron), API (external), SYSTEM (internal)';
COMMENT ON COLUMN streamsage.ai_analysis_request.request_context_json IS 'Additional context data for the analysis request';
COMMENT ON COLUMN streamsage.ai_analysis_request.requested_by_actor_type_cd IS 'Type of actor making the request';

-- Apply update timestamp trigger
CREATE OR REPLACE TRIGGER trg_ai_analysis_request_update_ts BEFORE UPDATE ON streamsage.ai_analysis_request
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();