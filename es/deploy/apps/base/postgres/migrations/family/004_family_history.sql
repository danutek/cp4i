-- =====================================================
-- StreamSage Enhanced Database Schema - Family History
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Audit trail for family changes and events
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- TRANSACTION FAMILY HISTORY TABLE
-- Purpose: Complete audit trail of family changes and membership events
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_family_history (
    tx_family_hist_uid BIGSERIAL,
    tx_family_uid BIGINT NOT NULL
        REFERENCES streamsage.tx_family(tx_family_uid),
    event_type_cd VARCHAR(30) NOT NULL,
    event_desc VARCHAR(1000),
    affected_tx_uid BIGINT
        REFERENCES streamsage.hub_transaction(tx_uid),
    old_value_json JSONB,
    new_value_json JSONB,
    event_user VARCHAR(60) NOT NULL,
    event_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system_cd VARCHAR(30),
    row_status_cd CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT pk_tx_family_history PRIMARY KEY (tx_family_hist_uid),
    CONSTRAINT fk_tx_family_hist_family FOREIGN KEY (tx_family_uid) REFERENCES streamsage.tx_family (tx_family_uid),
    CONSTRAINT fk_tx_family_hist_tx FOREIGN KEY (affected_tx_uid) REFERENCES streamsage.hub_transaction (tx_uid),
    CONSTRAINT chk_tx_family_hist_status CHECK (row_status_cd IN ('A', 'I', 'D'))
);

CREATE INDEX IF NOT EXISTS idx_tx_family_hist_family ON streamsage.tx_family_history (tx_family_uid, event_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_family_hist_tx ON streamsage.tx_family_history (affected_tx_uid, event_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_family_hist_event ON streamsage.tx_family_history (event_type_cd, event_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_family_hist_user ON streamsage.tx_family_history (event_user, event_ts DESC);

COMMENT ON TABLE streamsage.tx_family_history IS 'Complete audit trail of family changes, membership events, and state transitions';
COMMENT ON COLUMN streamsage.tx_family_history.event_type_cd IS 'Type of event (e.g., FAMILY_CREATED, MEMBER_ADDED, MEMBER_REMOVED, PRIMARY_CHANGED, STATUS_CHANGED)';
COMMENT ON COLUMN streamsage.tx_family_history.old_value_json IS 'Previous state before the change';
COMMENT ON COLUMN streamsage.tx_family_history.new_value_json IS 'New state after the change';