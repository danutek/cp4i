-- =====================================================
-- StreamSage Enhanced Database Schema - Family Indexes
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Additional indexes for family tables (supplemental to inline indexes)
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- FAMILY MEMBER INDEXES
-- =====================================================

-- Transaction lookup in families
CREATE INDEX IF NOT EXISTS idx_txfm_tx_uid
    ON streamsage.tx_family_member(tx_uid);

-- Family membership lookup
CREATE INDEX IF NOT EXISTS idx_txfm_family_uid
    ON streamsage.tx_family_member(tx_family_uid);

-- Active membership lookup with temporal validity
CREATE INDEX IF NOT EXISTS idx_txfm_active_membership
    ON streamsage.tx_family_member(tx_uid, effective_from_ts, effective_to_ts)
    WHERE row_status_cd = 'A' AND effective_to_ts IS NULL;

-- Primary transaction lookup
CREATE INDEX IF NOT EXISTS idx_txfm_primary
    ON streamsage.tx_family_member(tx_family_uid, is_primary_indc)
    WHERE is_primary_indc = 'Y';

-- =====================================================
-- FAMILY INDEXES
-- =====================================================

-- Family status lookup
CREATE INDEX IF NOT EXISTS idx_tx_family_status
    ON streamsage.tx_family(family_status_cd);

-- Business key lookup for family matching
CREATE INDEX IF NOT EXISTS idx_tx_family_business_key
    ON streamsage.tx_family(application_id, family_business_key);

-- Open families lookup
CREATE INDEX IF NOT EXISTS idx_tx_family_open
    ON streamsage.tx_family(application_id, family_type_cd, open_ts DESC)
    WHERE close_ts IS NULL AND row_status_cd = 'A';

COMMENT ON INDEX streamsage.idx_txfm_active_membership IS 'Optimizes queries for currently active family memberships';
COMMENT ON INDEX streamsage.idx_tx_family_open IS 'Optimizes queries for open/active families';