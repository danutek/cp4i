-- =====================================================================
-- File: 11_outbox.sql
-- Purpose: Transactional outbox table for StreamSage
-- Schema: streamsage
-- Database: PostgreSQL
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS streamsage;

CREATE TABLE IF NOT EXISTS streamsage.event_outbox (
    outbox_id               BIGSERIAL PRIMARY KEY,

    -- Aggregate / routing identity
    aggregate_type_cd       VARCHAR(50)  NOT NULL,
    aggregate_uid           BIGINT       NOT NULL,
    event_type_cd           VARCHAR(100) NOT NULL,
    event_version_cd        VARCHAR(20)  NOT NULL DEFAULT '1.0',
    event_key               VARCHAR(200) NOT NULL,

    -- Event payload
    payload_json            JSONB        NOT NULL,
    headers_json            JSONB        NULL,

    -- Source / traceability
    source_system_cd        VARCHAR(50)  NULL,
    correlation_id          UUID         NULL,
    causation_id            UUID         NULL,
    idempotency_key         VARCHAR(200) NULL,

    -- Publishing lifecycle
    publish_status_cd       VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    publish_attempt_count   INTEGER      NOT NULL DEFAULT 0,
    next_attempt_ts         TIMESTAMPTZ  NULL,
    published_ts            TIMESTAMPTZ  NULL,

    -- Error tracking
    last_error_cd           VARCHAR(100) NULL,
    last_error_msg          TEXT         NULL,

    -- Audit
    create_ts               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_id               VARCHAR(60)  NOT NULL,
    update_ts               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_id               VARCHAR(60)  NOT NULL,

    CONSTRAINT chk_event_outbox_status
        CHECK (publish_status_cd IN ('PENDING', 'PUBLISHED', 'FAILED', 'RETRY')),

    CONSTRAINT uq_event_outbox_idempotency
        UNIQUE (idempotency_key)
);

-- ---------------------------------------------------------------------
-- Helpful indexes
-- ---------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS ix_event_outbox_status_next_attempt
    ON streamsage.event_outbox (publish_status_cd, next_attempt_ts, create_ts);

CREATE INDEX IF NOT EXISTS ix_event_outbox_aggregate
    ON streamsage.event_outbox (aggregate_type_cd, aggregate_uid, create_ts);

CREATE INDEX IF NOT EXISTS ix_event_outbox_event_type
    ON streamsage.event_outbox (event_type_cd, create_ts);

CREATE INDEX IF NOT EXISTS ix_event_outbox_correlation_id
    ON streamsage.event_outbox (correlation_id);

CREATE INDEX IF NOT EXISTS ix_event_outbox_published_ts
    ON streamsage.event_outbox (published_ts);

-- ---------------------------------------------------------------------
-- Trigger to maintain update_ts
-- ---------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_event_outbox_update_ts
ON streamsage.event_outbox;

CREATE OR REPLACE TRIGGER trg_event_outbox_update_ts
BEFORE UPDATE ON streamsage.event_outbox
FOR EACH ROW
EXECUTE FUNCTION streamsage.update_timestamp();

-- ---------------------------------------------------------------------
-- Table / column comments
-- ---------------------------------------------------------------------

COMMENT ON TABLE streamsage.event_outbox IS
'Transactional outbox table for reliable publication of domain events to Kafka.';

COMMENT ON COLUMN streamsage.event_outbox.aggregate_type_cd IS
'Business aggregate type, e.g. TRANSACTION, TRANSACTION_FAMILY, APPROVAL.';

COMMENT ON COLUMN streamsage.event_outbox.aggregate_uid IS
'Primary database identifier of the business aggregate.';

COMMENT ON COLUMN streamsage.event_outbox.event_type_cd IS
'Canonical event type, e.g. transaction.created.';

COMMENT ON COLUMN streamsage.event_outbox.event_version_cd IS
'Semantic or contract version of the event payload.';

COMMENT ON COLUMN streamsage.event_outbox.event_key IS
'Kafka message key to preserve ordering, usually tx_uid or tx_family_uid.';

COMMENT ON COLUMN streamsage.event_outbox.payload_json IS
'Canonical event payload to publish.';

COMMENT ON COLUMN streamsage.event_outbox.headers_json IS
'Optional event headers and metadata to publish with the message.';

COMMENT ON COLUMN streamsage.event_outbox.publish_status_cd IS
'Publishing lifecycle state: PENDING, RETRY, PUBLISHED, FAILED.';

COMMENT ON COLUMN streamsage.event_outbox.publish_attempt_count IS
'Number of publish attempts made by the outbox publisher.';

COMMENT ON COLUMN streamsage.event_outbox.next_attempt_ts IS
'Timestamp after which the publisher may retry this row.';

COMMENT ON COLUMN streamsage.event_outbox.published_ts IS
'Timestamp when the event was successfully published.';

COMMENT ON COLUMN streamsage.event_outbox.idempotency_key IS
'Optional unique id for deduplication across retries or upstream replay.';