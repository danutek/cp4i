-- =====================================================
-- StreamSage Enhanced Database Schema - Transaction Families
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Transaction family grouping for related transactions
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- TRANSACTION FAMILY TABLE
-- Purpose: Groups related transactions into families for collective management
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_family (
    tx_family_uid BIGSERIAL,
    application_id INTEGER NOT NULL
        REFERENCES streamsage.apps(application_id),
    family_type_cd VARCHAR(30) NOT NULL,
    family_status_cd VARCHAR(20) NOT NULL,
    family_business_key VARCHAR(200),
    family_key_type_cd VARCHAR(30),
    originating_tx_uid BIGINT
        REFERENCES streamsage.hub_transaction(tx_uid),
    current_primary_tx_uid BIGINT
        REFERENCES streamsage.hub_transaction(tx_uid),
    open_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    close_ts TIMESTAMP,
    create_id VARCHAR(60) NOT NULL,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(60) NOT NULL,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT pk_tx_family PRIMARY KEY (tx_family_uid),
    CONSTRAINT fk_tx_family_app FOREIGN KEY (application_id) REFERENCES streamsage.apps (application_id),
    CONSTRAINT fk_tx_family_orig_tx FOREIGN KEY (originating_tx_uid) REFERENCES streamsage.hub_transaction (tx_uid),
    CONSTRAINT fk_tx_family_primary_tx FOREIGN KEY (current_primary_tx_uid) REFERENCES streamsage.hub_transaction (tx_uid),
    CONSTRAINT chk_tx_family_status CHECK (row_status_cd IN ('A', 'I', 'D'))
);

CREATE INDEX IF NOT EXISTS idx_tx_family_app ON streamsage.tx_family (application_id, family_type_cd);
CREATE INDEX IF NOT EXISTS idx_tx_family_orig_tx ON streamsage.tx_family (originating_tx_uid);
CREATE INDEX IF NOT EXISTS idx_tx_family_primary_tx ON streamsage.tx_family (current_primary_tx_uid);

COMMENT ON TABLE streamsage.tx_family IS 'Groups related transactions into families for collective management and processing';
COMMENT ON COLUMN streamsage.tx_family.family_business_key IS 'Business-level identifier for the family (e.g., account number, customer ID)';
COMMENT ON COLUMN streamsage.tx_family.originating_tx_uid IS 'The transaction that initiated this family';
COMMENT ON COLUMN streamsage.tx_family.current_primary_tx_uid IS 'The current primary/active transaction in the family';

-- Apply update timestamp trigger
CREATE OR REPLACE TRIGGER trg_tx_family_update_ts BEFORE UPDATE ON streamsage.tx_family
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();