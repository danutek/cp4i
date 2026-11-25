-- StreamSage Enhanced Database Schema - User & Security
-- Version: 2.0
-- Database: PostgreSQL
-- Description: User management, roles, permissions, and access control
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

CREATE TABLE IF NOT EXISTS streamsage.app_user (
    user_cnum VARCHAR(10) PRIMARY KEY,
    intranet_id VARCHAR(254) NOT NULL UNIQUE,
    notes_email_id VARCHAR(64) NOT NULL UNIQUE,
    ad_hoc_user_id VARCHAR(32),
    emp_name VARCHAR(100),
    emp_first_name VARCHAR(50),
    emp_last_name VARCHAR(50),
    emp_title VARCHAR(100),
    emp_department VARCHAR(100),
    emp_geo_code CHAR(4),
    emp_country_cd VARCHAR(3),
    emp_location VARCHAR(100),
    manager_cnum VARCHAR(10) REFERENCES streamsage.app_user(user_cnum),
    phone_number VARCHAR(20),
    mobile_number VARCHAR(20),
    time_zone VARCHAR(50),
    language_cd VARCHAR(5) DEFAULT 'en',
    application_id INTEGER REFERENCES streamsage.apps(application_id),
    is_active CHAR(1) NOT NULL DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    is_locked CHAR(1) NOT NULL DEFAULT 'N' CHECK (is_locked IN ('Y','N')),
    locked_reason VARCHAR(500),
    locked_ts TIMESTAMP,
    last_login_ts TIMESTAMP,
    last_login_ip VARCHAR(45),
    login_count INTEGER DEFAULT 0,
    failed_login_count INTEGER DEFAULT 0,
    last_failed_login_ts TIMESTAMP,
    password_changed_ts TIMESTAMP,
    must_change_password CHAR(1) DEFAULT 'N' CHECK (must_change_password IN ('Y','N')),
    profile_image_url VARCHAR(500),
    preferences_json JSONB,
    notification_settings_json JSONB,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I' CHECK (row_status_cd IN ('I','H','D'))
);

CREATE TABLE IF NOT EXISTS streamsage.dimension (
    dimension_id SERIAL PRIMARY KEY,
    dimension_code VARCHAR(20) NOT NULL UNIQUE,
    dimension_name VARCHAR(80) NOT NULL,
    dimension_desc VARCHAR(500),
    dimension_type VARCHAR(20) DEFAULT 'STANDARD' CHECK (dimension_type IN ('STANDARD','GEOGRAPHIC','ORGANIZATIONAL','TEMPORAL','CUSTOM')),
    schema_name VARCHAR(32),
    table_name VARCHAR(32),
    value_column VARCHAR(32),
    display_column VARCHAR(32),
    parent_dimension_id INTEGER REFERENCES streamsage.dimension(dimension_id),
    is_hierarchical CHAR(1) DEFAULT 'N' CHECK (is_hierarchical IN ('Y','N')),
    is_active CHAR(1) NOT NULL DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    display_order INTEGER,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I' CHECK (row_status_cd IN ('I','H','D'))
);

CREATE TABLE IF NOT EXISTS streamsage.access_authorization (
    access_auth_uid BIGSERIAL PRIMARY KEY,
    application_id INTEGER NOT NULL REFERENCES streamsage.apps(application_id),
    user_cnum VARCHAR(10) NOT NULL REFERENCES streamsage.app_user(user_cnum),
    dimension_id INTEGER NOT NULL REFERENCES streamsage.dimension(dimension_id),
    dimension_value VARCHAR(100) NOT NULL,
    access_level VARCHAR(20) NOT NULL DEFAULT 'READ' CHECK (access_level IN ('READ','WRITE','DELETE','ADMIN','FULL')),
    effective_from_dt DATE NOT NULL,
    effective_to_dt DATE,
    is_active CHAR(1) NOT NULL DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    granted_by VARCHAR(10),
    granted_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    grant_reason VARCHAR(500),
    adhoc_id CHAR(8),
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I' CHECK (row_status_cd IN ('I','H','D')),
    UNIQUE(application_id, user_cnum, dimension_id, dimension_value, effective_from_dt)
);

CREATE TABLE IF NOT EXISTS streamsage.role_definition (
    role_id SERIAL PRIMARY KEY,
    role_code VARCHAR(50) NOT NULL,
    role_name VARCHAR(100) NOT NULL,
    role_desc VARCHAR(500),
    role_type VARCHAR(20) DEFAULT 'FUNCTIONAL' CHECK (role_type IN ('FUNCTIONAL','ORGANIZATIONAL','SYSTEM','CUSTOM')),
    application_id INTEGER REFERENCES streamsage.apps(application_id),
    parent_role_id INTEGER REFERENCES streamsage.role_definition(role_id),
    is_system_role CHAR(1) DEFAULT 'N' CHECK (is_system_role IN ('Y','N')),
    is_active CHAR(1) NOT NULL DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    display_order INTEGER,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I' CHECK (row_status_cd IN ('I','H','D')),
    UNIQUE(role_code, application_id)
);

CREATE TABLE IF NOT EXISTS streamsage.permission_definition (
    permission_id SERIAL PRIMARY KEY,
    permission_code VARCHAR(50) NOT NULL UNIQUE,
    permission_name VARCHAR(100) NOT NULL,
    permission_desc VARCHAR(500),
    permission_category VARCHAR(50),
    application_id INTEGER REFERENCES streamsage.apps(application_id),
    resource_type VARCHAR(50),
    action_type VARCHAR(50),
    is_active CHAR(1) NOT NULL DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I' CHECK (row_status_cd IN ('I','H','D'))
);
