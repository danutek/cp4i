-- =====================================================
-- StreamSage Enhanced Database Schema - Audit & Logging
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Comprehensive audit trail and event logging
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- Transaction Audit Log
CREATE TABLE IF NOT EXISTS streamsage.tx_audit_log (
    audit_log_uid BIGSERIAL PRIMARY KEY,
    tx_uid BIGINT NOT NULL REFERENCES streamsage.hub_transaction(tx_uid),
    audit_action VARCHAR(20) NOT NULL CHECK (audit_action IN ('INSERT','UPDATE','DELETE','STATE_CHANGE','LOCK','UNLOCK','APPROVE','REJECT','SUBMIT','CANCEL','RESTORE')),
    audit_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    audit_user_id VARCHAR(10) NOT NULL,
    audit_user_name VARCHAR(100),
    table_name VARCHAR(100) NOT NULL,
    record_id VARCHAR(100),
    old_values JSONB,
    new_values JSONB,
    changed_fields VARCHAR(2000),
    change_reason VARCHAR(500),
    change_category VARCHAR(50),
    ip_address VARCHAR(45),
    user_agent VARCHAR(500),
    session_id VARCHAR(100),
    request_id VARCHAR(100),
    application_id INTEGER REFERENCES streamsage.apps(application_id),
    severity_level VARCHAR(20) DEFAULT 'INFO' CHECK (severity_level IN ('DEBUG','INFO','WARNING','ERROR','CRITICAL')),
    is_sensitive CHAR(1) DEFAULT 'N' CHECK (is_sensitive IN ('Y','N')),
    retention_days INTEGER DEFAULT 2555
);

CREATE INDEX IF NOT EXISTS idx_tx_audit_tx ON streamsage.tx_audit_log(tx_uid, audit_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_audit_ts ON streamsage.tx_audit_log(audit_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_audit_user ON streamsage.tx_audit_log(audit_user_id, audit_ts DESC);

-- Event Log
CREATE TABLE IF NOT EXISTS streamsage.tx_event_log (
    event_uid BIGSERIAL PRIMARY KEY,
    tx_uid BIGINT NOT NULL REFERENCES streamsage.hub_transaction(tx_uid),
    event_type VARCHAR(50) NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    event_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    event_user_id VARCHAR(10) NOT NULL,
    event_data JSONB,
    event_source VARCHAR(100),
    event_category VARCHAR(50),
    aggregate_version INTEGER NOT NULL,
    correlation_id VARCHAR(100),
    causation_id VARCHAR(100),
    is_processed CHAR(1) DEFAULT 'N' CHECK (is_processed IN ('Y','N')),
    processed_ts TIMESTAMP,
    processing_error VARCHAR(2000),
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3
);

CREATE INDEX IF NOT EXISTS idx_tx_event_tx ON streamsage.tx_event_log(tx_uid, event_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_event_type ON streamsage.tx_event_log(event_type, event_ts DESC);

-- Activity Log
CREATE TABLE IF NOT EXISTS streamsage.tx_activity_log (
    activity_uid BIGSERIAL PRIMARY KEY,
    tx_uid BIGINT NOT NULL REFERENCES streamsage.hub_transaction(tx_uid) ON DELETE CASCADE,
    activity_type VARCHAR(50) NOT NULL,
    activity_desc VARCHAR(1000) NOT NULL,
    activity_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    activity_user_id VARCHAR(10) NOT NULL,
    activity_user_name VARCHAR(100),
    activity_icon VARCHAR(50),
    activity_color VARCHAR(20),
    is_system_generated CHAR(1) DEFAULT 'N' CHECK (is_system_generated IN ('Y','N')),
    is_visible_to_user CHAR(1) DEFAULT 'Y' CHECK (is_visible_to_user IN ('Y','N')),
    related_entity_type VARCHAR(50),
    related_entity_id VARCHAR(100),
    metadata_json JSONB,
    row_status_cd CHAR(1) DEFAULT 'I' CHECK (row_status_cd IN ('I','H','D'))
);

CREATE INDEX IF NOT EXISTS idx_tx_activity_tx ON streamsage.tx_activity_log(tx_uid, activity_ts DESC);

-- Performance Metrics
CREATE TABLE IF NOT EXISTS streamsage.tx_performance_metrics (
    metric_uid BIGSERIAL PRIMARY KEY,
    tx_uid BIGINT REFERENCES streamsage.hub_transaction(tx_uid),
    metric_name VARCHAR(100) NOT NULL,
    metric_value DECIMAL(20,4) NOT NULL,
    metric_unit VARCHAR(20),
    metric_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metric_category VARCHAR(50),
    application_id INTEGER REFERENCES streamsage.apps(application_id),
    tx_type_cd VARCHAR(20),
    workstream_cd VARCHAR(20),
    aggregation_period VARCHAR(20),
    metadata_json JSONB
);

CREATE INDEX IF NOT EXISTS idx_tx_perf_tx ON streamsage.tx_performance_metrics(tx_uid, metric_ts DESC);

-- Error Log
CREATE TABLE IF NOT EXISTS streamsage.tx_error_log (
    error_uid BIGSERIAL PRIMARY KEY,
    tx_uid BIGINT REFERENCES streamsage.hub_transaction(tx_uid),
    error_code VARCHAR(50) NOT NULL,
    error_message VARCHAR(2000) NOT NULL,
    error_detail TEXT,
    error_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    error_source VARCHAR(200),
    error_severity VARCHAR(20) NOT NULL CHECK (error_severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    error_category VARCHAR(50),
    stack_trace TEXT,
    user_id VARCHAR(10),
    session_id VARCHAR(100),
    request_id VARCHAR(100),
    application_id INTEGER REFERENCES streamsage.apps(application_id),
    is_resolved CHAR(1) DEFAULT 'N' CHECK (is_resolved IN ('Y','N')),
    resolved_ts TIMESTAMP,
    resolved_by VARCHAR(10),
    resolution_notes VARCHAR(2000)
);

CREATE INDEX IF NOT EXISTS idx_tx_error_tx ON streamsage.tx_error_log(tx_uid, error_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_error_unresolved ON streamsage.tx_error_log(is_resolved, error_ts DESC) WHERE is_resolved = 'N';

-- Integration Log
CREATE TABLE IF NOT EXISTS streamsage.tx_integration_log (
    integration_log_uid BIGSERIAL PRIMARY KEY,
    tx_uid BIGINT REFERENCES streamsage.hub_transaction(tx_uid),
    integration_type VARCHAR(50) NOT NULL,
    external_system VARCHAR(100) NOT NULL,
    external_ref_id VARCHAR(200),
    direction VARCHAR(20) NOT NULL CHECK (direction IN ('INBOUND','OUTBOUND')),
    request_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    response_ts TIMESTAMP,
    duration_ms INTEGER,
    status_code VARCHAR(20),
    status_message VARCHAR(500),
    request_payload TEXT,
    response_payload TEXT,
    request_headers JSONB,
    response_headers JSONB,
    endpoint_url VARCHAR(1000),
    http_method VARCHAR(10),
    is_success CHAR(1) DEFAULT 'Y' CHECK (is_success IN ('Y','N')),
    error_message VARCHAR(2000),
    retry_count INTEGER DEFAULT 0,
    correlation_id VARCHAR(100)
);

CREATE INDEX IF NOT EXISTS idx_tx_integration_tx ON streamsage.tx_integration_log(tx_uid, request_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_integration_system ON streamsage.tx_integration_log(external_system, request_ts DESC);
