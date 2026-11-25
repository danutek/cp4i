-- =====================================================
-- StreamSage Enhanced Database Schema - AI Retrieval Context
-- Version: 2.0
-- Database: PostgreSQL
-- Description: RAG (Retrieval-Augmented Generation) context tracking
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- AI RETRIEVAL CONTEXT TABLE
-- Purpose: Tracks retrieved context items for RAG-based AI analysis
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.ai_retrieval_context (
    ai_retrieval_context_uid     BIGSERIAL PRIMARY KEY,
    ai_analysis_request_uid      BIGINT NOT NULL REFERENCES streamsage.ai_analysis_request(ai_analysis_request_uid),
    retrieval_source_cd          VARCHAR(40) NOT NULL,
    retrieval_item_type_cd       VARCHAR(40) NOT NULL,
    retrieval_item_ref_txt       VARCHAR(500) NOT NULL,
    retrieval_rank_num           INTEGER,
    similarity_score_num         NUMERIC(8,6),
    selected_indc                CHAR(1) NOT NULL DEFAULT 'Y',
    snippet_txt                  TEXT,
    metadata_json                JSONB,
    create_id                    VARCHAR(60) NOT NULL,
    create_ts                    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd                CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT chk_airc_source CHECK (
        retrieval_source_cd IN ('SQL','VECTOR','HYBRID','DOCUMENT','POLICY','CASE_HISTORY','KNOWLEDGE_BASE')
    ),
    CONSTRAINT chk_airc_item_type CHECK (
        retrieval_item_type_cd IN ('TX_FAMILY','TRANSACTION','DOCUMENT','RULE','POLICY','COMMENT','ATTACHMENT','SUMMARY')
    ),
    CONSTRAINT chk_airc_selected CHECK (selected_indc IN ('Y','N')),
    CONSTRAINT chk_airc_row_status CHECK (row_status_cd IN ('A','I','D'))
);

CREATE INDEX IF NOT EXISTS idx_ai_retrieval_request ON streamsage.ai_retrieval_context (ai_analysis_request_uid, retrieval_rank_num);
CREATE INDEX IF NOT EXISTS idx_ai_retrieval_source ON streamsage.ai_retrieval_context (retrieval_source_cd, selected_indc);
CREATE INDEX IF NOT EXISTS idx_ai_retrieval_type ON streamsage.ai_retrieval_context (retrieval_item_type_cd, similarity_score_num DESC);
CREATE INDEX IF NOT EXISTS idx_ai_retrieval_score ON streamsage.ai_retrieval_context (similarity_score_num DESC) WHERE selected_indc = 'Y';

COMMENT ON TABLE streamsage.ai_retrieval_context IS 'Tracks retrieved context items for RAG (Retrieval-Augmented Generation) based AI analysis';
COMMENT ON COLUMN streamsage.ai_retrieval_context.retrieval_source_cd IS 'Source of retrieval: SQL (database query), VECTOR (semantic search), HYBRID (combined), DOCUMENT (file), POLICY (rules), CASE_HISTORY (past cases), KNOWLEDGE_BASE (KB articles)';
COMMENT ON COLUMN streamsage.ai_retrieval_context.retrieval_item_type_cd IS 'Type of retrieved item: TX_FAMILY, TRANSACTION, DOCUMENT, RULE, POLICY, COMMENT, ATTACHMENT, SUMMARY';
COMMENT ON COLUMN streamsage.ai_retrieval_context.similarity_score_num IS 'Similarity/relevance score (0.0 to 1.0) for vector/semantic search';
COMMENT ON COLUMN streamsage.ai_retrieval_context.selected_indc IS 'Whether this item was selected for inclusion in the AI prompt';
COMMENT ON COLUMN streamsage.ai_retrieval_context.snippet_txt IS 'Text snippet or summary of the retrieved content';