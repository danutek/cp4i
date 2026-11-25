-- StreamSage Enhanced Database Schema - Reference Data
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Seed data for transaction states, relationship types, and dimensions
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- Transaction States
INSERT INTO streamsage.tx_state (tx_state_cd, tx_state_nm, tx_state_desc, is_terminal_state, display_order, state_color, create_id) VALUES
('DRAFT', 'Draft', 'Transaction is in draft state', 'N', 1, '#9E9E9E', 'SYSTEM'),
('SUBMITTED', 'Submitted', 'Transaction has been submitted for review', 'N', 2, '#2196F3', 'SYSTEM'),
('IN_REVIEW', 'In Review', 'Transaction is under review', 'N', 3, '#FF9800', 'SYSTEM'),
('PENDING_APPROVAL', 'Pending Approval', 'Waiting for approval', 'N', 4, '#FFC107', 'SYSTEM'),
('APPROVED', 'Approved', 'Transaction has been approved', 'N', 5, '#4CAF50', 'SYSTEM'),
('REJECTED', 'Rejected', 'Transaction has been rejected', 'Y', 6, '#F44336', 'SYSTEM'),
('IN_PROGRESS', 'In Progress', 'Transaction is being processed', 'N', 7, '#03A9F4', 'SYSTEM'),
('ON_HOLD', 'On Hold', 'Transaction is temporarily on hold', 'N', 8, '#FF5722', 'SYSTEM'),
('COMPLETED', 'Completed', 'Transaction has been completed', 'Y', 9, '#8BC34A', 'SYSTEM'),
('CANCELLED', 'Cancelled', 'Transaction has been cancelled', 'Y', 10, '#607D8B', 'SYSTEM'),
('ARCHIVED', 'Archived', 'Transaction has been archived', 'Y', 11, '#9E9E9E', 'SYSTEM')
ON CONFLICT DO NOTHING;

-- Relationship Types
INSERT INTO streamsage.tx_relationship_type (relationship_type_cd, relationship_type_nm, relationship_type_desc, is_bidirectional, allows_multiple, display_order, create_id) VALUES
('DEPENDS_ON', 'Depends On', 'This transaction depends on another transaction', 'Y', 'Y', 1, 'SYSTEM'),
('BLOCKS', 'Blocks', 'This transaction blocks another transaction', 'Y', 'Y', 2, 'SYSTEM'),
('RELATES_TO', 'Relates To', 'This transaction is related to another transaction', 'Y', 'Y', 3, 'SYSTEM'),
('SUPERSEDES', 'Supersedes', 'This transaction supersedes another transaction', 'Y', 'N', 4, 'SYSTEM'),
('DUPLICATES', 'Duplicates', 'This transaction is a duplicate of another transaction', 'Y', 'N', 6, 'SYSTEM')
ON CONFLICT DO NOTHING;

-- Dimensions
INSERT INTO streamsage.dimension (dimension_code, dimension_name, dimension_desc, dimension_type, is_hierarchical, is_active, display_order, create_id) VALUES
('GEOGRAPHY', 'Geography', 'Geographic dimension for access control', 'GEOGRAPHIC', 'Y', 'Y', 1, 'SYSTEM'),
('BUSINESS_UNIT', 'Business Unit', 'Business unit dimension', 'ORGANIZATIONAL', 'Y', 'Y', 2, 'SYSTEM'),
('PRODUCT_LINE', 'Product Line', 'Product line dimension', 'STANDARD', 'Y', 'Y', 3, 'SYSTEM')
ON CONFLICT DO NOTHING;
