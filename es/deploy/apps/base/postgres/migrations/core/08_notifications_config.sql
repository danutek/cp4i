-- StreamSage Enhanced Database Schema - Notifications & Configuration
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Notification templates and delivery queue
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

CREATE TABLE IF NOT EXISTS streamsage.notification_template (
    template_id SERIAL PRIMARY KEY,
    template_code VARCHAR(50) NOT NULL,
    template_name VARCHAR(100) NOT NULL,
    template_desc VARCHAR(500),
    notification_type VARCHAR(20) NOT NULL CHECK (notification_type IN ('EMAIL','SMS','IN_APP','PUSH','WEBHOOK')),
    subject_template VARCHAR(500),
    body_template TEXT NOT NULL,
    body_format VARCHAR(20) DEFAULT 'HTML' CHECK (body_format IN ('HTML','TEXT','MARKDOWN','JSON')),
    priority VARCHAR(20) DEFAULT 'NORMAL' CHECK (priority IN ('LOW','NORMAL','HIGH','URGENT')),
    application_id INTEGER REFERENCES streamsage.apps(application_id),
    event_type VARCHAR(50),
    language_cd VARCHAR(5) DEFAULT 'en',
    variables_json JSONB,
    attachment_allowed CHAR(1) DEFAULT 'N' CHECK (attachment_allowed IN ('Y','N')),
    is_active CHAR(1) NOT NULL DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I' CHECK (row_status_cd IN ('I','H','D')),
    UNIQUE(template_code, language_cd)
);

CREATE TABLE IF NOT EXISTS streamsage.notification_queue (
    notification_uid BIGSERIAL PRIMARY KEY,
    tx_uid BIGINT REFERENCES streamsage.hub_transaction(tx_uid),
    template_id INTEGER NOT NULL REFERENCES streamsage.notification_template(template_id),
    recipient_user_cnum VARCHAR(10) NOT NULL REFERENCES streamsage.app_user(user_cnum),
    recipient_email VARCHAR(254),
    recipient_phone VARCHAR(20),
    cc_recipients VARCHAR(2000),
    bcc_recipients VARCHAR(2000),
    notification_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (notification_status IN ('PENDING','PROCESSING','SENT','DELIVERED','READ','FAILED','CANCELLED','EXPIRED')),
    priority VARCHAR(20) DEFAULT 'NORMAL' CHECK (priority IN ('LOW','NORMAL','HIGH','URGENT')),
    subject VARCHAR(500),
    body TEXT,
    variables_json JSONB,
    scheduled_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sent_ts TIMESTAMP,
    delivered_ts TIMESTAMP,
    read_ts TIMESTAMP,
    clicked_ts TIMESTAMP,
    error_message VARCHAR(2000),
    error_code VARCHAR(50),
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    next_retry_ts TIMESTAMP,
    external_message_id VARCHAR(200),
    correlation_id VARCHAR(100),
    metadata_json JSONB,
    update_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id VARCHAR(10),
    create_id VARCHAR(10) NOT NULL,
    row_status_cd CHAR(1) NOT NULL DEFAULT 'I' CHECK (row_status_cd IN ('I','H','D'))
);

CREATE INDEX IF NOT EXISTS idx_notif_queue_pending ON streamsage.notification_queue(scheduled_ts) WHERE notification_status = 'PENDING';
