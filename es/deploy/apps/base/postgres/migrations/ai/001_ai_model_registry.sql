-- =====================================================
-- StreamSage Enhanced Database Schema - AI Model Registry
-- Version: 2.0
-- Database: PostgreSQL
-- Description: AI model catalog and configuration
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- AI MODEL REGISTRY TABLE
-- Purpose: Catalog of available AI models with capabilities and configuration
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.ai_model_registry (
    ai_model_uid                BIGSERIAL PRIMARY KEY,
    model_provider_cd           VARCHAR(40) NOT NULL,
    model_name                  VARCHAR(120) NOT NULL,
    model_version_cd            VARCHAR(60) NOT NULL,
    model_family_cd             VARCHAR(60),
    endpoint_ref_txt            VARCHAR(500),
    capability_json             JSONB,
    default_temperature_num     NUMERIC(4,3),
    default_max_tokens_num      INTEGER,
    active_indc                 CHAR(1) NOT NULL DEFAULT 'Y',
    effective_from_ts           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to_ts             TIMESTAMP,
    create_id                   VARCHAR(60) NOT NULL,
    create_ts                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id                   VARCHAR(60) NOT NULL,
    update_ts                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd               CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT chk_aimr_active_indc CHECK (active_indc IN ('Y','N')),
    CONSTRAINT chk_aimr_row_status CHECK (row_status_cd IN ('A','I','D')),
    CONSTRAINT chk_aimr_effective_ts CHECK (
        effective_to_ts IS NULL OR effective_to_ts >= effective_from_ts
    )
);

CREATE INDEX IF NOT EXISTS idx_ai_model_provider ON streamsage.ai_model_registry (model_provider_cd, active_indc);
CREATE INDEX IF NOT EXISTS idx_ai_model_family ON streamsage.ai_model_registry (model_family_cd, active_indc);
CREATE INDEX IF NOT EXISTS idx_ai_model_effective ON streamsage.ai_model_registry (effective_from_ts, effective_to_ts);

COMMENT ON TABLE streamsage.ai_model_registry IS 'Catalog of available AI models from various providers with capabilities and default parameters';
COMMENT ON COLUMN streamsage.ai_model_registry.model_provider_cd IS 'AI provider (e.g., OPENAI, ANTHROPIC, AZURE_OPENAI, BEDROCK, VERTEX_AI)';
COMMENT ON COLUMN streamsage.ai_model_registry.model_family_cd IS 'Model family grouping (e.g., GPT4, CLAUDE, GEMINI)';
COMMENT ON COLUMN streamsage.ai_model_registry.capability_json IS 'Model capabilities (e.g., max_tokens, supports_vision, supports_function_calling)';
COMMENT ON COLUMN streamsage.ai_model_registry.endpoint_ref_txt IS 'API endpoint or deployment reference';

-- Apply update timestamp trigger
CREATE OR REPLACE TRIGGER trg_ai_model_registry_update_ts BEFORE UPDATE ON streamsage.ai_model_registry
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();