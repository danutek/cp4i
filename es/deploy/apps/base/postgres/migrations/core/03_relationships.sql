-- =====================================================
-- StreamSage Enhanced Database Schema - Transaction Relationships
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Many-to-many transaction relationships
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- RELATIONSHIP TYPE TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_relationship_type (
    relationship_type_cd VARCHAR(20) NOT NULL,
    relationship_type_nm VARCHAR(100) NOT NULL,
    relationship_type_desc VARCHAR(500),
    is_bidirectional CHAR(1) NOT NULL DEFAULT 'N',
    inverse_relationship_cd VARCHAR(20),
    allows_multiple CHAR(1) NOT NULL DEFAULT 'Y',
    display_order INTEGER,
    icon_name VARCHAR(50),
    color_code VARCHAR(20),
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_tx_rel_type PRIMARY KEY (relationship_type_cd),
    CONSTRAINT fk_tx_rel_type_inverse FOREIGN KEY (inverse_relationship_cd) REFERENCES streamsage.tx_relationship_type (relationship_type_cd),
    CONSTRAINT chk_tx_rel_type_status CHECK (row_status_cd IN ('I', 'H', 'D')),
    CONSTRAINT chk_tx_rel_type_bidir CHECK (is_bidirectional IN ('Y', 'N')),
    CONSTRAINT chk_tx_rel_type_multiple CHECK (allows_multiple IN ('Y', 'N'))
);

CREATE INDEX IF NOT EXISTS idx_tx_rel_type_order ON streamsage.tx_relationship_type (display_order);

COMMENT ON TABLE streamsage.tx_relationship_type IS 'Defines types of relationships between transactions';

-- =====================================================
-- TRANSACTION RELATIONSHIP TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_relationship (
    tx_relationship_uid BIGSERIAL NOT NULL,
    source_tx_uid BIGINT NOT NULL,
    target_tx_uid BIGINT NOT NULL,
    relationship_type_cd VARCHAR(20) NOT NULL,
    relationship_desc VARCHAR(500),
    effective_from_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to_ts TIMESTAMP,
    is_active CHAR(1) NOT NULL DEFAULT 'Y',
    strength_level INTEGER DEFAULT 5,
    metadata_json JSONB,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_tx_relationship PRIMARY KEY (tx_relationship_uid),
    CONSTRAINT uk_tx_rel UNIQUE (source_tx_uid, target_tx_uid, relationship_type_cd, effective_from_ts),
    CONSTRAINT fk_tx_rel_source FOREIGN KEY (source_tx_uid) REFERENCES streamsage.hub_transaction (tx_uid),
    CONSTRAINT fk_tx_rel_target FOREIGN KEY (target_tx_uid) REFERENCES streamsage.hub_transaction (tx_uid),
    CONSTRAINT fk_tx_rel_type FOREIGN KEY (relationship_type_cd) REFERENCES streamsage.tx_relationship_type (relationship_type_cd),
    CONSTRAINT chk_tx_rel_status CHECK (row_status_cd IN ('I', 'H', 'D')),
    CONSTRAINT chk_tx_rel_active CHECK (is_active IN ('Y', 'N')),
    CONSTRAINT chk_tx_rel_strength CHECK (strength_level BETWEEN 1 AND 10),
    CONSTRAINT chk_tx_rel_not_self CHECK (source_tx_uid <> target_tx_uid)
);

CREATE INDEX IF NOT EXISTS idx_tx_rel_source ON streamsage.tx_relationship (source_tx_uid, relationship_type_cd);
CREATE INDEX IF NOT EXISTS idx_tx_rel_target ON streamsage.tx_relationship (target_tx_uid, relationship_type_cd);
CREATE INDEX IF NOT EXISTS idx_tx_rel_type ON streamsage.tx_relationship (relationship_type_cd, is_active);
CREATE INDEX IF NOT EXISTS idx_tx_rel_effective ON streamsage.tx_relationship (effective_from_ts, effective_to_ts);

COMMENT ON TABLE streamsage.tx_relationship IS 'Many-to-many relationships between transactions with temporal validity';

-- =====================================================
-- TRANSACTION COMMENTS TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_comment (
    comment_uid BIGSERIAL NOT NULL,
    tx_uid BIGINT NOT NULL,
    parent_comment_uid BIGINT,
    comment_text TEXT NOT NULL,
    comment_type VARCHAR(20) DEFAULT 'GENERAL',
    is_internal CHAR(1) NOT NULL DEFAULT 'N',
    is_pinned CHAR(1) NOT NULL DEFAULT 'N',
    mentioned_users VARCHAR(500),
    attachment_count INTEGER DEFAULT 0,
    like_count INTEGER DEFAULT 0,
    reply_count INTEGER DEFAULT 0,
    edited_ts TIMESTAMP,
    edited_by VARCHAR(10),
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_tx_comment PRIMARY KEY (comment_uid),
    CONSTRAINT fk_tx_comment_tx FOREIGN KEY (tx_uid) REFERENCES streamsage.hub_transaction (tx_uid) ON DELETE CASCADE,
    CONSTRAINT fk_tx_comment_parent FOREIGN KEY (parent_comment_uid) REFERENCES streamsage.tx_comment (comment_uid),
    CONSTRAINT chk_tx_comment_status CHECK (row_status_cd IN ('I', 'H', 'D')),
    CONSTRAINT chk_tx_comment_internal CHECK (is_internal IN ('Y', 'N')),
    CONSTRAINT chk_tx_comment_pinned CHECK (is_pinned IN ('Y', 'N')),
    CONSTRAINT chk_tx_comment_type CHECK (comment_type IN ('GENERAL', 'QUESTION', 'ANSWER', 'ISSUE', 'RESOLUTION', 'APPROVAL', 'REJECTION'))
);

CREATE INDEX IF NOT EXISTS idx_tx_comment_tx ON streamsage.tx_comment (tx_uid, create_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_comment_parent ON streamsage.tx_comment (parent_comment_uid);
CREATE INDEX IF NOT EXISTS idx_tx_comment_user ON streamsage.tx_comment (create_id, create_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_comment_pinned ON streamsage.tx_comment (tx_uid, is_pinned DESC) WHERE is_pinned = 'Y';

COMMENT ON TABLE streamsage.tx_comment IS 'Comments and discussions on transactions with threading support';

-- =====================================================
-- TRANSACTION TAGS TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_tag (
    tag_id SERIAL NOT NULL,
    tag_name VARCHAR(50) NOT NULL,
    tag_category VARCHAR(50),
    tag_color VARCHAR(20),
    tag_icon VARCHAR(50),
    tag_desc VARCHAR(500),
    application_id INTEGER,
    usage_count INTEGER DEFAULT 0,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_tx_tag PRIMARY KEY (tag_id),
    CONSTRAINT uk_tx_tag_name UNIQUE (tag_name, application_id),
    CONSTRAINT fk_tx_tag_app FOREIGN KEY (application_id) REFERENCES streamsage.apps (application_id),
    CONSTRAINT chk_tx_tag_status CHECK (row_status_cd IN ('I', 'H', 'D'))
);

CREATE INDEX IF NOT EXISTS idx_tx_tag_name ON streamsage.tx_tag (tag_name);
CREATE INDEX IF NOT EXISTS idx_tx_tag_category ON streamsage.tx_tag (tag_category);
CREATE INDEX IF NOT EXISTS idx_tx_tag_usage ON streamsage.tx_tag (usage_count DESC);

COMMENT ON TABLE streamsage.tx_tag IS 'Tag definitions for categorizing and organizing transactions';

-- =====================================================
-- TRANSACTION TAG ASSIGNMENT TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_tag_assignment (
    tx_tag_assign_uid BIGSERIAL NOT NULL,
    tx_uid BIGINT NOT NULL,
    tag_id INTEGER NOT NULL,
    assigned_by VARCHAR(10) NOT NULL,
    assigned_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_tx_tag_assign PRIMARY KEY (tx_tag_assign_uid),
    CONSTRAINT uk_tx_tag_assign UNIQUE (tx_uid, tag_id),
    CONSTRAINT fk_tx_tag_assign_tx FOREIGN KEY (tx_uid) REFERENCES streamsage.hub_transaction (tx_uid) ON DELETE CASCADE,
    CONSTRAINT fk_tx_tag_assign_tag FOREIGN KEY (tag_id) REFERENCES streamsage.tx_tag (tag_id),
    CONSTRAINT chk_tx_tag_assign_status CHECK (row_status_cd IN ('I', 'H', 'D'))
);

CREATE INDEX IF NOT EXISTS idx_tx_tag_assign_tx ON streamsage.tx_tag_assignment (tx_uid);
CREATE INDEX IF NOT EXISTS idx_tx_tag_assign_tag ON streamsage.tx_tag_assignment (tag_id);

COMMENT ON TABLE streamsage.tx_tag_assignment IS 'Assignment of tags to transactions';

-- Apply update timestamp triggers
CREATE OR REPLACE TRIGGER trg_tx_rel_type_update_ts BEFORE UPDATE ON streamsage.tx_relationship_type
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();

CREATE OR REPLACE TRIGGER trg_tx_relationship_update_ts BEFORE UPDATE ON streamsage.tx_relationship
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();

CREATE OR REPLACE TRIGGER trg_tx_comment_update_ts BEFORE UPDATE ON streamsage.tx_comment
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();

CREATE OR REPLACE TRIGGER trg_tx_tag_update_ts BEFORE UPDATE ON streamsage.tx_tag
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();


