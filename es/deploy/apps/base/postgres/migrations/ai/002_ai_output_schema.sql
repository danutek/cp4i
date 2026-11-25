-- =====================================================
-- StreamSage Enhanced Database Schema - AI Output Schema
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Structured output schema definitions for AI responses
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- AI OUTPUT SCHEMA TABLE
-- Purpose: Defines structured output schemas for AI model responses
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.ai_output_schema (
    ai_output_schema_uid        BIGSERIAL PRIMARY KEY,
    schema_cd                   VARCHAR(80) NOT NULL,
    schema_version_cd           VARCHAR(30) NOT NULL,
    schema_format_cd            VARCHAR(20) NOT NULL,
    schema_definition_json      JSONB NOT NULL,
    active_indc                 CHAR(1) NOT NULL DEFAULT 'Y',
    effective_from_ts           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to_ts             TIMESTAMP,
    create_id                   VARCHAR(60) NOT NULL,
    create_ts                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id                   VARCHAR(60) NOT NULL,
    update_ts                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd               CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT chk_aios_format CHECK (schema_format_cd IN ('JSON_SCHEMA','AVRO','TEXT')),
    CONSTRAINT chk_aios_active CHECK (active_indc IN ('Y','N')),
    CONSTRAINT chk_aios_row_status CHECK (row_status_cd IN ('A','I','D')),
    CONSTRAINT chk_aios_effective_ts CHECK (
        effective_to_ts IS NULL OR effective_to_ts >= effective_from_ts
    )
);

CREATE INDEX IF NOT EXISTS idx_ai_output_schema_code ON streamsage.ai_output_schema (schema_cd, schema_version_cd);
CREATE INDEX IF NOT EXISTS idx_ai_output_schema_format ON streamsage.ai_output_schema (schema_format_cd, active_indc);
CREATE INDEX IF NOT EXISTS idx_ai_output_schema_effective ON streamsage.ai_output_schema (effective_from_ts, effective_to_ts);

COMMENT ON TABLE streamsage.ai_output_schema IS 'Structured output schema definitions for AI model responses to ensure consistent formatting';
COMMENT ON COLUMN streamsage.ai_output_schema.schema_format_cd IS 'Schema format type (JSON_SCHEMA for structured JSON, AVRO for data serialization, TEXT for unstructured)';
COMMENT ON COLUMN streamsage.ai_output_schema.schema_definition_json IS 'The actual schema definition in the specified format';

-- Apply update timestamp trigger
CREATE OR REPLACE TRIGGER trg_ai_output_schema_update_ts BEFORE UPDATE ON streamsage.ai_output_schema
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();