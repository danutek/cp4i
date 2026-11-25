-- =====================================================
-- StreamSage Enhanced Database Schema - Family Members
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Transaction membership in families with roles and temporal validity
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- TRANSACTION FAMILY MEMBER TABLE
-- Purpose: Tracks which transactions belong to which families and their roles
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.tx_family_member (
    tx_family_uid BIGINT NOT NULL
        REFERENCES streamsage.tx_family(tx_family_uid),
    tx_uid BIGINT NOT NULL
        REFERENCES streamsage.hub_transaction(tx_uid),
    member_role_cd VARCHAR(30) NOT NULL,
    membership_reason_cd VARCHAR(30) NOT NULL,
    is_primary_indc CHAR(1) NOT NULL DEFAULT 'N',
    is_originating_indc CHAR(1) NOT NULL DEFAULT 'N',
    effective_from_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to_ts TIMESTAMP,
    create_id VARCHAR(60) NOT NULL,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(60) NOT NULL,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT pk_tx_family_member PRIMARY KEY (tx_family_uid, tx_uid, effective_from_ts),
    CONSTRAINT fk_tx_family_member_family FOREIGN KEY (tx_family_uid) REFERENCES streamsage.tx_family (tx_family_uid),
    CONSTRAINT fk_tx_family_member_tx FOREIGN KEY (tx_uid) REFERENCES streamsage.hub_transaction (tx_uid),
    CONSTRAINT chk_tx_family_member_status CHECK (row_status_cd IN ('A', 'I', 'D')),
    CONSTRAINT chk_tx_family_member_primary CHECK (is_primary_indc IN ('Y', 'N')),
    CONSTRAINT chk_tx_family_member_orig CHECK (is_originating_indc IN ('Y', 'N')),
    CONSTRAINT chk_tx_family_member_effective CHECK (effective_to_ts IS NULL OR effective_to_ts >= effective_from_ts)
);

COMMENT ON TABLE streamsage.tx_family_member IS 'Tracks transaction membership in families with roles and temporal validity';
COMMENT ON COLUMN streamsage.tx_family_member.member_role_cd IS 'Role of the transaction within the family (e.g., PRIMARY, CHILD, RELATED)';
COMMENT ON COLUMN streamsage.tx_family_member.membership_reason_cd IS 'Reason for family membership (e.g., MANUAL, AUTO_MATCHED, INHERITED)';
COMMENT ON COLUMN streamsage.tx_family_member.is_primary_indc IS 'Indicates if this is the primary/active transaction in the family';
COMMENT ON COLUMN streamsage.tx_family_member.is_originating_indc IS 'Indicates if this transaction originated the family';

-- Apply update timestamp trigger
CREATE OR REPLACE TRIGGER trg_tx_family_member_update_ts BEFORE UPDATE ON streamsage.tx_family_member
    FOR EACH ROW EXECUTE FUNCTION streamsage.update_timestamp();