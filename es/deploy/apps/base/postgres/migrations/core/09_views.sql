-- StreamSage Enhanced Database Schema - Views
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Convenience views for common queries
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

CREATE OR REPLACE VIEW streamsage.apps_v AS
SELECT * FROM streamsage.apps WHERE row_status_cd <> 'D';

CREATE OR REPLACE VIEW streamsage.app_user_v AS
SELECT * FROM streamsage.app_user WHERE row_status_cd <> 'D';

CREATE OR REPLACE VIEW streamsage.hub_transaction_v AS
SELECT * FROM streamsage.hub_transaction WHERE row_status_cd <> 'D';

CREATE OR REPLACE VIEW streamsage.hub_transaction_active_v AS
SELECT * FROM streamsage.hub_transaction
WHERE row_status_cd = 'I'
AND tx_state_cd NOT IN (SELECT tx_state_cd FROM streamsage.tx_state WHERE is_terminal_state = 'Y');

CREATE OR REPLACE VIEW streamsage.tx_current_state_v AS
SELECT 
    t.tx_uid,
    t.op_tx_line_uid,
    t.tx_type_cd,
    t.tx_state_cd,
    s.tx_state_nm,
    s.is_terminal_state,
    t.create_ts AS tx_create_ts,
    t.update_ts AS tx_update_ts,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - t.create_ts))/3600 AS age_hours,
    CASE 
        WHEN t.due_date IS NOT NULL AND CURRENT_DATE > t.due_date THEN 'OVERDUE'
        WHEN t.due_date IS NOT NULL AND CURRENT_DATE = t.due_date THEN 'DUE_TODAY'
        WHEN t.due_date IS NOT NULL AND (t.due_date - CURRENT_DATE) <= 3 THEN 'DUE_SOON'
        ELSE 'ON_TRACK'
    END AS due_status
FROM streamsage.hub_transaction t
INNER JOIN streamsage.tx_state s ON t.tx_state_cd = s.tx_state_cd
WHERE t.row_status_cd <> 'D' AND s.row_status_cd <> 'D';

CREATE OR REPLACE VIEW streamsage.pending_notifications_v AS
SELECT 
    n.notification_uid,
    n.tx_uid,
    t.op_tx_line_uid,
    n.template_id,
    nt.template_name,
    nt.notification_type,
    n.recipient_user_cnum,
    u.emp_name AS recipient_name,
    n.recipient_email,
    n.notification_status,
    n.priority,
    n.scheduled_ts,
    n.retry_count,
    n.max_retries
FROM streamsage.notification_queue n
INNER JOIN streamsage.notification_template nt ON n.template_id = nt.template_id
LEFT JOIN streamsage.hub_transaction t ON n.tx_uid = t.tx_uid
LEFT JOIN streamsage.app_user u ON n.recipient_user_cnum = u.user_cnum
WHERE n.row_status_cd <> 'D'
AND n.notification_status IN ('PENDING', 'FAILED')
AND (n.notification_status = 'PENDING' OR n.retry_count < n.max_retries)
AND n.scheduled_ts <= CURRENT_TIMESTAMP;
