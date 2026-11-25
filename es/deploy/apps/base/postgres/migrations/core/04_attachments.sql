-- =====================================================
-- StreamSage Enhanced Database Schema - Enhanced Attachments
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Enhanced attachment management with categories and metadata
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- ATTACHMENT CATEGORY TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.attachment_category (
    category_id SERIAL NOT NULL,
    category_code VARCHAR(50) NOT NULL,
    category_name VARCHAR(100) NOT NULL,
    category_desc VARCHAR(500),
    parent_category_id INTEGER,
    allowed_file_types VARCHAR(500),
    max_file_size_mb INTEGER DEFAULT 100,
    requires_approval CHAR(1) DEFAULT 'N',
    retention_days INTEGER,
    is_versioned CHAR(1) DEFAULT 'Y',
    display_order INTEGER,
    icon_name VARCHAR(50),
    application_id INTEGER,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_attach_category PRIMARY KEY (category_id),
    CONSTRAINT uk_attach_cat_code UNIQUE (category_code, application_id),
    CONSTRAINT fk_attach_cat_parent FOREIGN KEY (parent_category_id) REFERENCES streamsage.attachment_category (category_id),
    CONSTRAINT fk_attach_cat_app FOREIGN KEY (application_id) REFERENCES streamsage.apps (application_id),
    CONSTRAINT chk_attach_cat_status CHECK (row_status_cd IN ('I', 'H', 'D')),
    CONSTRAINT chk_attach_cat_approval CHECK (requires_approval IN ('Y', 'N')),
    CONSTRAINT chk_attach_cat_versioned CHECK (is_versioned IN ('Y', 'N'))
);

CREATE INDEX IF NOT EXISTS idx_attach_cat_code ON streamsage.attachment_category (category_code);
CREATE INDEX IF NOT EXISTS idx_attach_cat_parent ON streamsage.attachment_category (parent_category_id);

COMMENT ON TABLE streamsage.attachment_category IS 'Hierarchical categorization of attachments with rules';

-- =====================================================
-- REPOSITORY CONFIGURATION TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.repository_config (
    repository_id SERIAL NOT NULL,
    repository_code VARCHAR(50) NOT NULL,
    repository_name VARCHAR(100) NOT NULL,
    repository_type VARCHAR(50) NOT NULL,
    connection_string VARCHAR(500),
    access_key_id VARCHAR(200),
    secret_access_key VARCHAR(500),
    bucket_name VARCHAR(200),
    region VARCHAR(50),
    endpoint_url VARCHAR(500),
    is_primary CHAR(1) DEFAULT 'N',
    is_active CHAR(1) DEFAULT 'Y',
    max_storage_gb INTEGER,
    current_usage_gb DECIMAL(10,2) DEFAULT 0,
    config_json JSONB,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_repository_config PRIMARY KEY (repository_id),
    CONSTRAINT uk_repository_code UNIQUE (repository_code),
    CONSTRAINT chk_repository_status CHECK (row_status_cd IN ('I', 'H', 'D')),
    CONSTRAINT chk_repository_primary CHECK (is_primary IN ('Y', 'N')),
    CONSTRAINT chk_repository_active CHECK (is_active IN ('Y', 'N')),
    CONSTRAINT chk_repository_type CHECK (repository_type IN ('OBJECTSTORAGE', 'S3', 'AZURE_BLOB', 'GCS', 'FILESYSTEM', 'SHAREPOINT', 'BOX', 'DROPBOX'))
);

CREATE INDEX IF NOT EXISTS idx_repository_type ON streamsage.repository_config (repository_type, is_active);
CREATE INDEX IF NOT EXISTS idx_repository_primary ON streamsage.repository_config (is_primary DESC) WHERE is_primary = 'Y';

COMMENT ON TABLE streamsage.repository_config IS 'Multi-cloud repository configuration for file storage';

-- =====================================================
-- HUBTX ATTACHMENTS TABLE (Enhanced)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.hubtx_attachments (
    hubtx_attach_uid BIGSERIAL NOT NULL,
    tx_uid BIGINT NOT NULL,
    file_nm VARCHAR(500) NOT NULL,
    file_version_num INTEGER NOT NULL DEFAULT 1,
    file_desc VARCHAR(1000),
    file_status_cd VARCHAR(20) NOT NULL DEFAULT 'ATT_ST_100',
    category_id INTEGER,
    document_type_cd VARCHAR(50),
    repository_id INTEGER NOT NULL,
    repository_type_cd VARCHAR(50) NOT NULL DEFAULT 'OBJECTSTORAGE',
    cm_id VARCHAR(500) NOT NULL,
    storage_path VARCHAR(1000),
    filesize_num BIGINT,
    file_extension VARCHAR(20),
    mime_type VARCHAR(100),
    checksum VARCHAR(64),
    checksum_algorithm VARCHAR(20) DEFAULT 'SHA256',
    encryption_status VARCHAR(20) DEFAULT 'NONE',
    encryption_key_id VARCHAR(100),
    is_virus_scanned CHAR(1) DEFAULT 'N',
    virus_scan_status VARCHAR(20),
    virus_scan_ts TIMESTAMP,
    thumbnail_path VARCHAR(1000),
    preview_available CHAR(1) DEFAULT 'N',
    is_searchable CHAR(1) DEFAULT 'Y',
    extracted_text TEXT,
    ocr_processed CHAR(1) DEFAULT 'N',
    retention_policy_id INTEGER,
    expiration_date DATE,
    download_count INTEGER DEFAULT 0,
    last_accessed_ts TIMESTAMP,
    last_accessed_by VARCHAR(10),
    tocm_strt_ts TIMESTAMP,
    tocm_end_ts TIMESTAMP,
    tohub_start_ts TIMESTAMP,
    tohub_end_ts TIMESTAMP,
    cm_version_num INTEGER DEFAULT 1,
    cm_upldfail_ct INTEGER DEFAULT 0,
    app_versionbuild_txt VARCHAR(50),
    meta_config_id INTEGER,
    metaconfig_version_num INTEGER,
    hubtx_attachtype_cd VARCHAR(50),
    custom_value_1 VARCHAR(500),
    custom_value_2 VARCHAR(500),
    custom_value_3 VARCHAR(500),
    custom_value_4 VARCHAR(500),
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_hubtx_attach PRIMARY KEY (hubtx_attach_uid),
    CONSTRAINT fk_hubtx_attach_tx FOREIGN KEY (tx_uid) REFERENCES streamsage.hub_transaction (tx_uid) ON DELETE CASCADE,
    CONSTRAINT fk_hubtx_attach_cat FOREIGN KEY (category_id) REFERENCES streamsage.attachment_category (category_id),
    CONSTRAINT fk_hubtx_attach_repo FOREIGN KEY (repository_id) REFERENCES streamsage.repository_config (repository_id),
    CONSTRAINT chk_hubtx_attach_status CHECK (row_status_cd IN ('I', 'H', 'D')),
    CONSTRAINT chk_hubtx_attach_scanned CHECK (is_virus_scanned IN ('Y', 'N')),
    CONSTRAINT chk_hubtx_attach_preview CHECK (preview_available IN ('Y', 'N')),
    CONSTRAINT chk_hubtx_attach_searchable CHECK (is_searchable IN ('Y', 'N')),
    CONSTRAINT chk_hubtx_attach_ocr CHECK (ocr_processed IN ('Y', 'N')),
    CONSTRAINT chk_hubtx_attach_encrypt CHECK (encryption_status IN ('NONE', 'AT_REST', 'IN_TRANSIT', 'BOTH'))
);

CREATE INDEX IF NOT EXISTS idx_hubtx_attach_tx ON streamsage.hubtx_attachments (tx_uid, file_status_cd);
CREATE INDEX IF NOT EXISTS idx_hubtx_attach_type ON streamsage.hubtx_attachments (document_type_cd, create_ts DESC);
CREATE INDEX IF NOT EXISTS idx_hubtx_attach_cat ON streamsage.hubtx_attachments (category_id);
CREATE INDEX IF NOT EXISTS idx_hubtx_attach_checksum ON streamsage.hubtx_attachments (checksum);
CREATE INDEX IF NOT EXISTS idx_hubtx_attach_expiry ON streamsage.hubtx_attachments (expiration_date) WHERE expiration_date IS NOT NULL;

COMMENT ON TABLE streamsage.hubtx_attachments IS 'Enhanced attachment management with security, versioning, and multi-repository support';

-- =====================================================
-- ATTACHMENT METADATA TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.attachment_metadata (
    metadata_uid BIGSERIAL NOT NULL,
    hubtx_attach_uid BIGINT NOT NULL,
    metadata_key VARCHAR(100) NOT NULL,
    metadata_value VARCHAR(4000),
    metadata_type VARCHAR(20) DEFAULT 'STRING',
    is_indexed CHAR(1) DEFAULT 'N',
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_attach_metadata PRIMARY KEY (metadata_uid),
    CONSTRAINT uk_attach_metadata UNIQUE (hubtx_attach_uid, metadata_key),
    CONSTRAINT fk_attach_metadata FOREIGN KEY (hubtx_attach_uid) REFERENCES streamsage.hubtx_attachments (hubtx_attach_uid) ON DELETE CASCADE,
    CONSTRAINT chk_attach_meta_status CHECK (row_status_cd IN ('I', 'H', 'D')),
    CONSTRAINT chk_attach_meta_indexed CHECK (is_indexed IN ('Y', 'N')),
    CONSTRAINT chk_attach_meta_type CHECK (metadata_type IN ('STRING', 'NUMBER', 'DATE', 'JSON', 'BOOLEAN'))
);

CREATE INDEX IF NOT EXISTS idx_attach_meta_attach ON streamsage.attachment_metadata (hubtx_attach_uid);
CREATE INDEX IF NOT EXISTS idx_attach_meta_key ON streamsage.attachment_metadata (metadata_key);
CREATE INDEX IF NOT EXISTS idx_attach_meta_value ON streamsage.attachment_metadata (metadata_value) WHERE is_indexed = 'Y';

COMMENT ON TABLE streamsage.attachment_metadata IS 'Flexible metadata for attachments';

-- =====================================================
-- ATTACHMENT RELATIONSHIP TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.attachment_relationship (
    attach_rel_uid BIGSERIAL NOT NULL,
    source_attach_uid BIGINT NOT NULL,
    target_attach_uid BIGINT NOT NULL,
    relationship_type VARCHAR(20) NOT NULL,
    relationship_desc VARCHAR(500),
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_attach_rel PRIMARY KEY (attach_rel_uid),
    CONSTRAINT uk_attach_rel UNIQUE (source_attach_uid, target_attach_uid, relationship_type),
    CONSTRAINT fk_attach_rel_source FOREIGN KEY (source_attach_uid) REFERENCES streamsage.hubtx_attachments (hubtx_attach_uid),
    CONSTRAINT fk_attach_rel_target FOREIGN KEY (target_attach_uid) REFERENCES streamsage.hubtx_attachments (hubtx_attach_uid),
    CONSTRAINT chk_attach_rel_status CHECK (row_status_cd IN ('I', 'H', 'D')),
    CONSTRAINT chk_attach_rel_type CHECK (relationship_type IN ('SUPERSEDES', 'REPLACES', 'SUPPLEMENTS', 'DERIVED_FROM', 'RELATED_TO', 'THUMBNAIL_OF', 'PREVIEW_OF')),
    CONSTRAINT chk_attach_rel_not_self CHECK (source_attach_uid <> target_attach_uid)
);

CREATE INDEX IF NOT EXISTS idx_attach_rel_source ON streamsage.attachment_relationship (source_attach_uid);
CREATE INDEX IF NOT EXISTS idx_attach_rel_target ON streamsage.attachment_relationship (target_attach_uid);

COMMENT ON TABLE streamsage.attachment_relationship IS 'Relationships between attachments (versioning, derivation, etc.)';

-- Apply update timestamp triggers
CREATE OR REPLACE TRIGGER trg_attach_cat_update_ts BEFORE UPDATE ON streamsage.attachment_category
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();

CREATE OR REPLACE TRIGGER trg_repository_config_update_ts BEFORE UPDATE ON streamsage.repository_config
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();

CREATE OR REPLACE TRIGGER trg_hubtx_attach_update_ts BEFORE UPDATE ON streamsage.hubtx_attachments
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();

CREATE OR REPLACE TRIGGER trg_attach_meta_update_ts BEFORE UPDATE ON streamsage.attachment_metadata
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();

CREATE OR REPLACE TRIGGER trg_attach_rel_update_ts BEFORE UPDATE ON streamsage.attachment_relationship
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();
