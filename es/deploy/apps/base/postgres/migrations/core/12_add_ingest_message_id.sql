ALTER TABLE streamsage.hub_transaction
    ADD COLUMN IF NOT EXISTS ingest_message_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uk_hub_transaction_ingest_message_id
    ON streamsage.hub_transaction (ingest_message_id)
    WHERE ingest_message_id IS NOT NULL;
