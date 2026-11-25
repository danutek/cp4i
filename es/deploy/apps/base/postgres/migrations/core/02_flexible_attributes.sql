-- =====================================================
-- StreamSage Enhanced Database Schema - Flexible Attributes
-- Version: 2.0
-- Database: PostgreSQL
-- Description: EAV pattern for extensible transaction attributes
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- ATTRIBUTE DEFINITION TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_attribute_def (
    attribute_id SERIAL NOT NULL,
    attribute_code VARCHAR(50) NOT NULL,
    attribute_name VARCHAR(100) NOT NULL,
    attribute_desc VARCHAR(500),
    data_type VARCHAR(20) NOT NULL,
    is_required CHAR(1) NOT NULL DEFAULT 'N',
    is_searchable CHAR(1) NOT NULL DEFAULT 'Y',
    is_encrypted CHAR(1) NOT NULL DEFAULT 'N',
    default_value VARCHAR(500),
    validation_rule VARCHAR(1000),
    validation_message VARCHAR(500),
    min_value DECIMAL(20,4),
    max_value DECIMAL(20,4),
    min_length INTEGER,
    max_length INTEGER,
    allowed_values VARCHAR(2000),
    regex_pattern VARCHAR(500),
    application_id INTEGER,
    tx_type_cd VARCHAR(20),
    workstream_cd VARCHAR(20),
    display_order INTEGER,
    display_group VARCHAR(50),
    help_text VARCHAR(1000),
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_tx_attr_def PRIMARY KEY (attribute_id),
    CONSTRAINT uk_tx_attr_code UNIQUE (attribute_code, application_id, tx_type_cd),
    CONSTRAINT fk_tx_attr_app FOREIGN KEY (application_id) REFERENCES streamsage.apps (application_id),
    CONSTRAINT chk_tx_attr_status CHECK (row_status_cd IN ('I', 'H', 'D')),
    CONSTRAINT chk_tx_attr_required CHECK (is_required IN ('Y', 'N')),
    CONSTRAINT chk_tx_attr_searchable CHECK (is_searchable IN ('Y', 'N')),
    CONSTRAINT chk_tx_attr_encrypted CHECK (is_encrypted IN ('Y', 'N')),
    CONSTRAINT chk_tx_attr_data_type CHECK (data_type IN ('STRING', 'NUMBER', 'DATE', 'DATETIME', 'BOOLEAN', 'JSON', 'DECIMAL', 'INTEGER', 'EMAIL', 'URL', 'PHONE'))
);

CREATE INDEX IF NOT EXISTS idx_tx_attr_code ON streamsage.tx_attribute_def (attribute_code);
CREATE INDEX IF NOT EXISTS idx_tx_attr_app ON streamsage.tx_attribute_def (application_id, tx_type_cd);
CREATE INDEX IF NOT EXISTS idx_tx_attr_type ON streamsage.tx_attribute_def (data_type);

COMMENT ON TABLE streamsage.tx_attribute_def IS 'Flexible attribute definitions for extensible transaction properties';

-- =====================================================
-- ATTRIBUTE VALUE TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_attribute_value (
    tx_attr_value_uid BIGSERIAL NOT NULL,
    tx_uid BIGINT NOT NULL,
    attribute_id INTEGER NOT NULL,
    string_value VARCHAR(4000),
    number_value DECIMAL(20,4),
    date_value DATE,
    datetime_value TIMESTAMP,
    boolean_value CHAR(1),
    json_value JSONB,
    encrypted_value VARCHAR(4000),
    value_hash VARCHAR(64),
    is_valid CHAR(1) DEFAULT 'Y',
    validation_error VARCHAR(500),
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_tx_attr_value PRIMARY KEY (tx_attr_value_uid),
    CONSTRAINT uk_tx_attr_value UNIQUE (tx_uid, attribute_id),
    CONSTRAINT fk_tx_attr_val_tx FOREIGN KEY (tx_uid) REFERENCES streamsage.hub_transaction (tx_uid) ON DELETE CASCADE,
    CONSTRAINT fk_tx_attr_val_def FOREIGN KEY (attribute_id) REFERENCES streamsage.tx_attribute_def (attribute_id),
    CONSTRAINT chk_tx_attr_val_status CHECK (row_status_cd IN ('I', 'H', 'D')),
    CONSTRAINT chk_tx_attr_val_bool CHECK (boolean_value IN ('Y', 'N', NULL)),
    CONSTRAINT chk_tx_attr_val_valid CHECK (is_valid IN ('Y', 'N'))
);

CREATE INDEX IF NOT EXISTS idx_tx_attr_val_tx ON streamsage.tx_attribute_value (tx_uid, attribute_id);
CREATE INDEX IF NOT EXISTS idx_tx_attr_val_attr ON streamsage.tx_attribute_value (attribute_id);
CREATE INDEX IF NOT EXISTS idx_tx_attr_val_string ON streamsage.tx_attribute_value (string_value) WHERE string_value IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tx_attr_val_number ON streamsage.tx_attribute_value (number_value) WHERE number_value IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tx_attr_val_date ON streamsage.tx_attribute_value (date_value) WHERE date_value IS NOT NULL;

COMMENT ON TABLE streamsage.tx_attribute_value IS 'Flexible attribute values supporting multiple data types';

-- =====================================================
-- ATTRIBUTE VALUE HISTORY TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_attribute_value_history (
    tx_attr_val_hist_uid BIGSERIAL NOT NULL,
    tx_attr_value_uid BIGINT NOT NULL,
    tx_uid BIGINT NOT NULL,
    attribute_id INTEGER NOT NULL,
    old_string_value VARCHAR(4000),
    new_string_value VARCHAR(4000),
    old_number_value DECIMAL(20,4),
    new_number_value DECIMAL(20,4),
    old_date_value DATE,
    new_date_value DATE,
    old_boolean_value CHAR(1),
    new_boolean_value CHAR(1),
    change_type VARCHAR(20) NOT NULL,
    change_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    change_user_id VARCHAR(10) NOT NULL,
    change_reason VARCHAR(500),
    CONSTRAINT pk_tx_attr_val_hist PRIMARY KEY (tx_attr_val_hist_uid),
    CONSTRAINT fk_tx_attr_val_hist FOREIGN KEY (tx_attr_value_uid) REFERENCES streamsage.tx_attribute_value (tx_attr_value_uid),
    CONSTRAINT chk_tx_attr_val_hist_type CHECK (change_type IN ('INSERT', 'UPDATE', 'DELETE'))
);

CREATE INDEX IF NOT EXISTS idx_tx_attr_val_hist_val ON streamsage.tx_attribute_value_history (tx_attr_value_uid, change_ts DESC);
CREATE INDEX IF NOT EXISTS idx_tx_attr_val_hist_tx ON streamsage.tx_attribute_value_history (tx_uid, change_ts DESC);

COMMENT ON TABLE streamsage.tx_attribute_value_history IS 'History of attribute value changes for audit trail';

-- =====================================================
-- ATTRIBUTE GROUP TABLE (New)
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_attribute_group (
    group_id SERIAL NOT NULL,
    group_code VARCHAR(50) NOT NULL,
    group_name VARCHAR(100) NOT NULL,
    group_desc VARCHAR(500),
    parent_group_id INTEGER,
    display_order INTEGER,
    is_collapsible CHAR(1) DEFAULT 'Y',
    is_collapsed_default CHAR(1) DEFAULT 'N',
    application_id INTEGER,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I',
    CONSTRAINT pk_tx_attr_group PRIMARY KEY (group_id),
    CONSTRAINT uk_tx_attr_group_code UNIQUE (group_code, application_id),
    CONSTRAINT fk_tx_attr_group_parent FOREIGN KEY (parent_group_id) REFERENCES streamsage.tx_attribute_group (group_id),
    CONSTRAINT fk_tx_attr_group_app FOREIGN KEY (application_id) REFERENCES streamsage.apps (application_id),
    CONSTRAINT chk_tx_attr_group_status CHECK (row_status_cd IN ('I', 'H', 'D')),
    CONSTRAINT chk_tx_attr_group_collapsible CHECK (is_collapsible IN ('Y', 'N')),
    CONSTRAINT chk_tx_attr_group_collapsed CHECK (is_collapsed_default IN ('Y', 'N'))
);

CREATE INDEX IF NOT EXISTS idx_tx_attr_group_code ON streamsage.tx_attribute_group (group_code);
CREATE INDEX IF NOT EXISTS idx_tx_attr_group_parent ON streamsage.tx_attribute_group (parent_group_id);

COMMENT ON TABLE streamsage.tx_attribute_group IS 'Logical grouping of attributes for UI organization';

-- Apply update timestamp triggers
CREATE OR REPLACE TRIGGER trg_tx_attr_def_update_ts BEFORE UPDATE ON streamsage.tx_attribute_def
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();

CREATE OR REPLACE TRIGGER trg_tx_attr_value_update_ts BEFORE UPDATE ON streamsage.tx_attribute_value
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();

CREATE OR REPLACE TRIGGER trg_tx_attr_group_update_ts BEFORE UPDATE ON streamsage.tx_attribute_group
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();

