-- =====================================================
-- StreamSage Enhanced Database Schema - AI Action Execution
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Execution tracking for AI-recommended actions
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- AI ACTION EXECUTION TABLE
-- Purpose: Tracks the execution of AI-recommended actions with results and errors
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.ai_action_execution (
    ai_action_execution_uid       BIGSERIAL PRIMARY KEY,
    ai_recommendation_uid         BIGINT REFERENCES streamsage.ai_recommendation(ai_recommendation_uid),
    ai_recommendation_action_uid  BIGINT NOT NULL REFERENCES streamsage.ai_recommendation_action(ai_recommendation_action_uid),
    action_type_cd                VARCHAR(60) NOT NULL,
    execution_status_cd           VARCHAR(20) NOT NULL DEFAULT 'QUEUED',
    action_request_json           JSONB NOT NULL,
    action_result_json            JSONB,
    target_tx_uid                 BIGINT REFERENCES streamsage.hub_transaction(tx_uid),
    target_tx_family_uid          BIGINT REFERENCES streamsage.tx_family(tx_family_uid),
    target_workflow_id            INTEGER REFERENCES streamsage.workflow_definition(workflow_id),
    execution_service_cd          VARCHAR(60),
    execution_event_id            VARCHAR(100),
    requested_ts                  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_ts                    TIMESTAMP,
    completed_ts                  TIMESTAMP,
    executed_by_actor_type_cd     VARCHAR(20) NOT NULL DEFAULT 'SYSTEM',
    executed_by_actor_id          VARCHAR(100) NOT NULL,
    error_txt                     VARCHAR(4000),
    create_id                     VARCHAR(60) NOT NULL,
    create_ts                     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id                     VARCHAR(60) NOT NULL,
    update_ts                     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd                 CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT chk_aiae_status CHECK (
        execution_status_cd IN ('QUEUED','RUNNING','SUCCEEDED','FAILED','CANCELLED','SKIPPED')
    ),
    CONSTRAINT chk_aiae_actor_type CHECK (
        executed_by_actor_type_cd IN ('USER','SYSTEM','SERVICE','BATCH')
    ),
    CONSTRAINT chk_aiae_row_status CHECK (row_status_cd IN ('A','I','D')),
    CONSTRAINT chk_aiae_time_order CHECK (
        (started_ts IS NULL OR started_ts >= requested_ts) AND
        (completed_ts IS NULL OR started_ts IS NULL OR completed_ts >= started_ts)
    )
);

CREATE INDEX IF NOT EXISTS idx_ai_action_exec_rec ON streamsage.ai_action_execution (ai_recommendation_uid, requested_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_action_exec_action ON streamsage.ai_action_execution (ai_recommendation_action_uid, execution_status_cd);
CREATE INDEX IF NOT EXISTS idx_ai_action_exec_status ON streamsage.ai_action_execution (execution_status_cd, requested_ts);
CREATE INDEX IF NOT EXISTS idx_ai_action_exec_tx ON streamsage.ai_action_execution (target_tx_uid, requested_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_action_exec_family ON streamsage.ai_action_execution (target_tx_family_uid, requested_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_action_exec_type ON streamsage.ai_action_execution (action_type_cd, execution_status_cd);

COMMENT ON TABLE streamsage.ai_action_execution IS 'Tracks the execution of AI-recommended actions with detailed results, errors, and timing';
COMMENT ON COLUMN streamsage.ai_action_execution.execution_status_cd IS 'Status: QUEUED (waiting), RUNNING (in progress), SUCCEEDED (completed), FAILED (error), CANCELLED (aborted), SKIPPED (bypassed)';
COMMENT ON COLUMN streamsage.ai_action_execution.action_request_json IS 'The action request data sent for execution';
COMMENT ON COLUMN streamsage.ai_action_execution.action_result_json IS 'The result data returned from execution';
COMMENT ON COLUMN streamsage.ai_action_execution.execution_service_cd IS 'Service or component that executed the action';
COMMENT ON COLUMN streamsage.ai_action_execution.execution_event_id IS 'Event or transaction ID from the execution system';

-- Apply update timestamp trigger
CREATE OR REPLACE TRIGGER trg_ai_action_exec_update_ts BEFORE UPDATE ON streamsage.ai_action_execution
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();