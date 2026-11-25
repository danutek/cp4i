-- =====================================================
-- StreamSage Enhanced Database Schema - AI Prompt Templates
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Versioned prompt templates for AI interactions
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- AI PROMPT TEMPLATE TABLE
-- Purpose: Versioned prompt templates with system instructions and model preferences
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.ai_prompt_template (
    ai_prompt_template_uid      BIGSERIAL PRIMARY KEY,
    prompt_type_cd              VARCHAR(60) NOT NULL,
    prompt_name                 VARCHAR(120) NOT NULL,
    prompt_version_num          INTEGER NOT NULL,
    prompt_template_txt         TEXT NOT NULL,
    system_instruction_txt      TEXT,
    output_schema_uid           BIGINT REFERENCES streamsage.ai_output_schema(ai_output_schema_uid),
    preferred_ai_model_uid      BIGINT REFERENCES streamsage.ai_model_registry(ai_model_uid),
    model_family_cd             VARCHAR(60),
    temperature_num             NUMERIC(4,3),
    max_tokens_num              INTEGER,
    active_indc                 CHAR(1) NOT NULL DEFAULT 'Y',
    approval_required_indc      CHAR(1) NOT NULL DEFAULT 'N',
    effective_from_ts           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to_ts             TIMESTAMP,
    owner_id                    VARCHAR(60),
    create_id                   VARCHAR(60) NOT NULL,
    create_ts                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id                   VARCHAR(60) NOT NULL,
    update_ts                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd               CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT chk_aipt_active CHECK (active_indc IN ('Y','N')),
    CONSTRAINT chk_aipt_approval CHECK (approval_required_indc IN ('Y','N')),
    CONSTRAINT chk_aipt_row_status CHECK (row_status_cd IN ('A','I','D')),
    CONSTRAINT chk_aipt_prompt_version CHECK (prompt_version_num >= 1),
    CONSTRAINT chk_aipt_effective_ts CHECK (
        effective_to_ts IS NULL OR effective_to_ts >= effective_from_ts
    )
);

CREATE INDEX IF NOT EXISTS idx_ai_prompt_type ON streamsage.ai_prompt_template (prompt_type_cd, active_indc);
CREATE INDEX IF NOT EXISTS idx_ai_prompt_model ON streamsage.ai_prompt_template (preferred_ai_model_uid);
CREATE INDEX IF NOT EXISTS idx_ai_prompt_owner ON streamsage.ai_prompt_template (owner_id, active_indc);
CREATE INDEX IF NOT EXISTS idx_ai_prompt_effective ON streamsage.ai_prompt_template (effective_from_ts, effective_to_ts);

COMMENT ON TABLE streamsage.ai_prompt_template IS 'Versioned prompt templates for AI interactions with system instructions and model preferences';
COMMENT ON COLUMN streamsage.ai_prompt_template.prompt_type_cd IS 'Type of prompt (e.g., OBSERVATION, RECOMMENDATION, SUMMARY, TRIAGE, VALIDATION)';
COMMENT ON COLUMN streamsage.ai_prompt_template.prompt_template_txt IS 'The prompt template with variable placeholders (e.g., {{transaction_id}}, {{context}})';
COMMENT ON COLUMN streamsage.ai_prompt_template.system_instruction_txt IS 'System-level instructions that define the AI assistant behavior and constraints';
COMMENT ON COLUMN streamsage.ai_prompt_template.output_schema_uid IS 'Reference to expected output schema for structured responses';
COMMENT ON COLUMN streamsage.ai_prompt_template.approval_required_indc IS 'Whether prompt changes require approval before use';

-- Apply update timestamp trigger
CREATE OR REPLACE TRIGGER trg_ai_prompt_template_update_ts BEFORE UPDATE ON streamsage.ai_prompt_template
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();