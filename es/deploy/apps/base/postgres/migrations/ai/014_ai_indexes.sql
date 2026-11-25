-- =====================================================
-- StreamSage Enhanced Database Schema - AI Indexes
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Additional indexes for AI tables (supplemental to inline indexes)
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- AI MODEL REGISTRY INDEXES
-- =====================================================

CREATE UNIQUE INDEX IF NOT EXISTS uk_ai_model_registry_name_ver
    ON streamsage.ai_model_registry(model_provider_cd, model_name, model_version_cd)
    WHERE row_status_cd <> 'D';

CREATE INDEX IF NOT EXISTS idx_ai_model_registry_active
    ON streamsage.ai_model_registry(active_indc, effective_from_ts, effective_to_ts);

-- =====================================================
-- AI PROMPT TEMPLATE INDEXES
-- =====================================================

CREATE UNIQUE INDEX IF NOT EXISTS uk_ai_prompt_template_name_ver
    ON streamsage.ai_prompt_template(prompt_name, prompt_version_num)
    WHERE row_status_cd <> 'D';

CREATE INDEX IF NOT EXISTS idx_ai_prompt_template_type_active
    ON streamsage.ai_prompt_template(prompt_type_cd, active_indc, effective_from_ts, effective_to_ts);

-- =====================================================
-- AI POLICY RULE INDEXES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_ai_policy_rule_lookup
    ON streamsage.ai_policy_rule(action_type_cd, application_id, tx_type_cd, family_type_cd, workflow_type_cd, active_indc, priority_num);

-- =====================================================
-- AI ANALYSIS REQUEST INDEXES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_ai_analysis_request_status
    ON streamsage.ai_analysis_request(status_cd, request_priority_cd, requested_ts);

CREATE INDEX IF NOT EXISTS idx_ai_analysis_request_tx
    ON streamsage.ai_analysis_request(tx_uid, tx_family_uid, requested_ts DESC);

CREATE INDEX IF NOT EXISTS idx_ai_analysis_request_trigger
    ON streamsage.ai_analysis_request(trigger_event_id, trigger_event_type_cd);

-- =====================================================
-- AI CONTEXT SNAPSHOT INDEXES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_ai_context_snapshot_request
    ON streamsage.ai_context_snapshot(ai_analysis_request_uid, create_ts DESC);

CREATE INDEX IF NOT EXISTS idx_ai_context_snapshot_tx
    ON streamsage.ai_context_snapshot(tx_uid, tx_family_uid);

-- =====================================================
-- AI RETRIEVAL CONTEXT INDEXES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_ai_retrieval_context_request
    ON streamsage.ai_retrieval_context(ai_analysis_request_uid, retrieval_rank_num);

-- =====================================================
-- AI OBSERVATION INDEXES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_ai_observation_tx
    ON streamsage.ai_observation(tx_uid, tx_family_uid, create_ts DESC);

CREATE INDEX IF NOT EXISTS idx_ai_observation_type_status
    ON streamsage.ai_observation(observation_type_cd, observation_status_cd, create_ts DESC);

-- =====================================================
-- AI RECOMMENDATION INDEXES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_ai_recommendation_status
    ON streamsage.ai_recommendation(recommendation_status_cd, create_ts DESC);

CREATE INDEX IF NOT EXISTS idx_ai_recommendation_tx
    ON streamsage.ai_recommendation(tx_uid, tx_family_uid, create_ts DESC);

CREATE INDEX IF NOT EXISTS idx_ai_recommendation_type
    ON streamsage.ai_recommendation(recommendation_type_cd, create_ts DESC);

-- =====================================================
-- AI RECOMMENDATION ACTION INDEXES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_ai_recommendation_action_rec
    ON streamsage.ai_recommendation_action(ai_recommendation_uid, action_sequence_num);

CREATE INDEX IF NOT EXISTS idx_ai_recommendation_action_status
    ON streamsage.ai_recommendation_action(action_status_cd, execution_priority_cd, create_ts);

-- =====================================================
-- AI REVIEW DECISION INDEXES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_ai_review_decision_rec
    ON streamsage.ai_review_decision(ai_recommendation_uid, reviewed_ts DESC);

CREATE INDEX IF NOT EXISTS idx_ai_review_decision_action
    ON streamsage.ai_review_decision(ai_recommendation_action_uid, reviewed_ts DESC);

-- =====================================================
-- AI ACTION EXECUTION INDEXES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_ai_action_execution_status
    ON streamsage.ai_action_execution(execution_status_cd, requested_ts);

CREATE INDEX IF NOT EXISTS idx_ai_action_execution_target
    ON streamsage.ai_action_execution(target_tx_uid, target_tx_family_uid, requested_ts DESC);

-- =====================================================
-- INDEX COMMENTS
-- =====================================================

COMMENT ON INDEX streamsage.uk_ai_model_registry_name_ver IS 'Ensures unique model provider/name/version combinations';
COMMENT ON INDEX streamsage.uk_ai_prompt_template_name_ver IS 'Ensures unique prompt name/version combinations';
COMMENT ON INDEX streamsage.idx_ai_policy_rule_lookup IS 'Optimizes policy rule matching for AI action evaluation';
COMMENT ON INDEX streamsage.idx_ai_analysis_request_status IS 'Optimizes queries for pending and active AI analysis requests';
COMMENT ON INDEX streamsage.idx_ai_recommendation_status IS 'Optimizes queries for recommendations by status and recency';
COMMENT ON INDEX streamsage.idx_ai_action_execution_status IS 'Optimizes queries for action execution monitoring and retry logic';

