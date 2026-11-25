-- =====================================================
-- StreamSage Enhanced Database Schema - AI Context Snapshots
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Point-in-time context capture for AI analysis
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- AI CONTEXT SNAPSHOT TABLE
-- Purpose: Captures point-in-time context data for AI analysis requests
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.ai_context_snapshot (
    ai_context_snapshot_uid      BIGSERIAL PRIMARY KEY,
    ai_analysis_request_uid      BIGINT NOT NULL REFERENCES streamsage.ai_analysis_request(ai_analysis_request_uid),
    tx_uid                       BIGINT REFERENCES streamsage.hub_transaction(tx_uid),
    tx_family_uid                BIGINT REFERENCES streamsage.tx_family(tx_family_uid),
    context_version_num          INTEGER NOT NULL DEFAULT 1,
    context_json                 JSONB NOT NULL,
    context_hash_txt             VARCHAR(128),
    token_estimate_num           INTEGER,
    redaction_applied_indc       CHAR(1) NOT NULL DEFAULT 'N',
    create_id                    VARCHAR(60) NOT NULL,
    create_ts                    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd                CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT chk_aics_redaction CHECK (redaction_applied_indc IN ('Y','N')),
    CONSTRAINT chk_aics_row_status CHECK (row_status_cd IN ('A','I','D')),
    CONSTRAINT chk_aics_context_version CHECK (context_version_num >= 1)
);

CREATE INDEX IF NOT EXISTS idx_ai_context_request ON streamsage.ai_context_snapshot (ai_analysis_request_uid, context_version_num);
CREATE INDEX IF NOT EXISTS idx_ai_context_tx ON streamsage.ai_context_snapshot (tx_uid, create_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_context_family ON streamsage.ai_context_snapshot (tx_family_uid, create_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_context_hash ON streamsage.ai_context_snapshot (context_hash_txt);

COMMENT ON TABLE streamsage.ai_context_snapshot IS 'Point-in-time snapshots of context data for AI analysis, enabling reproducibility and audit';
COMMENT ON COLUMN streamsage.ai_context_snapshot.context_json IS 'Complete context data including transaction details, attributes, relationships, and history';
COMMENT ON COLUMN streamsage.ai_context_snapshot.context_hash_txt IS 'Hash of context for deduplication and change detection';
COMMENT ON COLUMN streamsage.ai_context_snapshot.token_estimate_num IS 'Estimated token count for LLM processing';
COMMENT ON COLUMN streamsage.ai_context_snapshot.redaction_applied_indc IS 'Whether sensitive data was redacted from the snapshot';