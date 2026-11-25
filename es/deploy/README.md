# StreamSage Enhanced Database Schema v2.0 - PostgreSQL (pg_02)

## Overview

This is the **PostgreSQL version** of the StreamSage Enhanced Transaction Hub database with updated terminology:
- **DNA** → **TX_LINE** (Transaction Line)
- **DEAL** → **OP** (Operation)

This version features a comprehensive redesign with significant improvements in flexibility, scalability, and maintainability, specifically optimized for PostgreSQL.

## Terminology Changes

### Key Naming Conventions

| Original Term | New Term | Description |
|--------------|----------|-------------|
| `deal_dna_uid` | `op_tx_line_uid` | Unique identifier for operations/transactions |
| `parent_deal_uid` | `parent_op_uid` | Parent operation reference |
| `dna_generate_indc` | `tx_line_generate_indc` | TX_LINE generation indicator |
| `dna_create_indc` | `tx_line_create_indc` | TX_LINE creation indicator |
| `new_dna_indc` | `new_tx_line_indc` | New TX_LINE indicator |
| `auto_generate_dna` | `auto_generate_tx_line` | Auto-generate TX_LINE flag |
| `dna_prefix` | `tx_line_prefix` | TX_LINE prefix for generation |
| `dna_pattern` | `tx_line_pattern` | TX_LINE pattern format |
| `app_dnalink_config` | `app_tx_linelink_config` | TX_LINE link configuration table |
| Deal | Op | Operation (in descriptions) |
| DNA | TX_LINE | Transaction Line (in descriptions) |

## Installation

### Prerequisites
- PostgreSQL 12.0 or higher
- Superuser or schema creation privileges
- Minimum 10GB disk space
- 4GB RAM recommended

### Quick Start

```bash
# Connect to PostgreSQL
psql -U postgres -d your_database

# Execute DDL files in order
\i 01_core_tables.sql
\i 02_flexible_attributes.sql
\i 03_relationships.sql
\i 04_attachments.sql
\i 05_audit_logging.sql
\i 06_workflow_engine.sql
\i 07_user_security.sql
\i 08_notifications_config.sql
\i 09_views.sql
\i 10_reference_data.sql
```

### Automated Installation

```bash
# Run all files in sequence
for file in {01..10}*.sql; do
    psql -U postgres -d your_database -f "$file"
done
```

## File Structure

```
pg_02/
├── 01_core_tables.sql              # Core transaction tables with triggers
├── 02_flexible_attributes.sql      # EAV pattern for extensibility
├── 03_relationships.sql            # Transaction relationships
├── 04_attachments.sql              # Enhanced attachment management
├── 05_audit_logging.sql            # Comprehensive audit trail
├── 06_workflow_engine.sql          # Workflow and business rules
├── 07_user_security.sql            # RBAC and user management
├── 08_notifications_config.sql     # Notification system
├── 09_views.sql                    # Reporting views
├── 10_reference_data.sql           # Initial seed data
└── README.md                       # This file
```

## Key Features

### 1. OP_TX_LINE_UID (Operation Transaction Line)
```sql
-- Store flexible operation identifier
INSERT INTO streamsage.hub_transaction (
    op_tx_line_uid,
    tx_type_cd,
    tx_line_generate_indc
) VALUES (
    '25061815ABC123',
    'OP',
    'Y'
);

-- Query by operation TX_LINE
SELECT * FROM streamsage.hub_transaction 
WHERE op_tx_line_uid = '25061815ABC123';
```

### 2. TX_LINE Generation Configuration
```sql
-- Configure TX_LINE generation for workflows
INSERT INTO streamsage.app_tx_linelink_config (
    application_id,
    tx_type_cd,
    workstream_cd,
    tx_line_create_indc,
    new_tx_line_indc,
    auto_generate_tx_line,
    tx_line_prefix,
    tx_line_pattern
) VALUES (
    1099,
    'PRICING',
    'PRICING',
    'N',
    'N',
    'Y',
    'PRC-',
    'YYMMDD-{seq:6}'
);
```

### 3. Parent-Child Operation Relationships
```sql
-- Create parent operation
INSERT INTO hub_transaction (
    op_tx_line_uid,
    tx_type_cd,
    tx_line_generate_indc,
    parent_op_uid
) VALUES (
    '25061815XYZ789',
    'OP',
    'Y',
    NULL  -- Parent has no parent
);

-- Create child operation
INSERT INTO hub_transaction (
    op_tx_line_uid,
    tx_type_cd,
    tx_line_generate_indc,
    parent_op_uid
) VALUES (
    '25061815XYZ789',  -- Same TX_LINE as parent
    'PRICING',
    'N',
    '25061815XYZ789'   -- References parent
);
```

### 4. JSONB for Flexibility
```sql
-- Store flexible configuration
INSERT INTO streamsage.apps (application_id, application_code, config_json)
VALUES (1, 'APP001', '{"theme": "dark", "features": ["notifications", "reports"]}');

-- Query JSON data
SELECT * FROM streamsage.apps 
WHERE config_json->>'theme' = 'dark';

-- Create GIN index for JSON queries
CREATE INDEX idx_apps_config_gin ON streamsage.apps USING GIN (config_json);
```

### 5. Automatic Timestamp Updates
```sql
-- Trigger function automatically updates update_ts
UPDATE streamsage.hub_transaction 
SET tx_state_cd = 'APPROVED' 
WHERE tx_uid = 1000;
-- update_ts is automatically set to CURRENT_TIMESTAMP
```

## Business Use Cases

### Use Case 1: Master Operation with Children
```
1. Create OP transaction (parent)
   - TX_TYPE_CD = 'OP'
   - TX_LINE_GENERATE_INDC = 'Y'
   - OP_TX_LINE_UID = '25061815ABC123' (auto-generated)
   - PARENT_OP_UID = NULL

2. Create PRICING transaction (child)
   - TX_TYPE_CD = 'PRICING'
   - TX_LINE_GENERATE_INDC = 'N'
   - OP_TX_LINE_UID = '25061815ABC123' (same as parent)
   - PARENT_OP_UID = '25061815ABC123' (references parent)

3. Create INVENTORY transaction (child)
   - TX_TYPE_CD = 'INVENTORY'
   - TX_LINE_GENERATE_INDC = 'N'
   - OP_TX_LINE_UID = '25061815ABC123' (same as parent)
   - PARENT_OP_UID = '25061815ABC123' (references parent)
```

### Use Case 2: Query All Related Transactions
```sql
-- Find all transactions related to an operation
SELECT 
    tx_uid,
    tx_type_cd,
    tx_line_generate_indc,
    parent_op_uid,
    create_ts
FROM hub_transaction
WHERE op_tx_line_uid = '25061815ABC123'
ORDER BY create_ts;

-- Result shows parent OP + all child transactions
```

### Use Case 3: TX_LINE Configuration by Workflow
```sql
-- Configure TX_LINE generation for PRICING workflow
INSERT INTO app_tx_linelink_config (
    application_id, tx_type_cd, workstream_cd,
    tx_line_create_indc, new_tx_line_indc, auto_generate_tx_line,
    tx_line_prefix, tx_line_pattern
) VALUES (
    1099, 'PRICING', 'PRICING',
    'N', 'N', 'Y',
    'PRC-', 'YYMMDD-{seq:6}'
);
```

## TX_LINE Naming Convention

Based on the original data pattern, the TX_LINE format:
```
YYMMDD + HH + RandomAlphanumeric

Examples:
- 25052017cX2MnKJ  = 2025-05-20 at 17:xx
- 25061815ABC123   = 2025-06-18 at 15:xx
- 250723049XYZ789  = 2025-07-23 at 04:xx
```

## Performance Optimization

### Partitioning (PostgreSQL 10+)
```sql
-- Partition hub_transaction by month
CREATE TABLE streamsage.hub_transaction_partitioned (
    LIKE streamsage.hub_transaction INCLUDING ALL
) PARTITION BY RANGE (create_ts);

-- Create monthly partitions
CREATE TABLE streamsage.hub_transaction_2026_01 
PARTITION OF streamsage.hub_transaction_partitioned
FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

CREATE TABLE streamsage.hub_transaction_2026_02 
PARTITION OF streamsage.hub_transaction_partitioned
FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
```

### Materialized Views
```sql
-- Create materialized view for reporting
CREATE MATERIALIZED VIEW streamsage.tx_summary_mv AS
SELECT 
    tx_type_cd,
    tx_state_cd,
    COUNT(*) as tx_count,
    AVG(EXTRACT(EPOCH FROM (update_ts - create_ts))/3600) as avg_duration_hours
FROM streamsage.hub_transaction
WHERE row_status_cd <> 'D'
GROUP BY tx_type_cd, tx_state_cd;

-- Create index on materialized view
CREATE INDEX idx_tx_summary_mv ON streamsage.tx_summary_mv (tx_type_cd, tx_state_cd);

-- Refresh materialized view
REFRESH MATERIALIZED VIEW CONCURRENTLY streamsage.tx_summary_mv;
```

### Connection Pooling
```bash
# Use PgBouncer for connection pooling
# /etc/pgbouncer/pgbouncer.ini
[databases]
streamsage = host=localhost port=5432 dbname=streamsage

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
```

## PostgreSQL-Specific Optimizations

### 1. VACUUM and ANALYZE
```sql
-- Regular maintenance
VACUUM ANALYZE streamsage.hub_transaction;

-- Auto-vacuum settings (postgresql.conf)
autovacuum = on
autovacuum_vacuum_scale_factor = 0.1
autovacuum_analyze_scale_factor = 0.05
```

### 2. Work Memory
```sql
-- Increase work_mem for complex queries
SET work_mem = '256MB';

-- Or in postgresql.conf
work_mem = 256MB
```

### 3. Parallel Query
```sql
-- Enable parallel query execution
SET max_parallel_workers_per_gather = 4;

-- Force parallel scan
SET parallel_setup_cost = 0;
SET parallel_tuple_cost = 0;
```

## Backup and Recovery

### Logical Backup
```bash
# Backup entire schema
pg_dump -U postgres -d your_database -n streamsage -F c -f streamsage_backup.dump

# Restore
pg_restore -U postgres -d your_database -n streamsage streamsage_backup.dump
```

### Point-in-Time Recovery
```bash
# Enable WAL archiving in postgresql.conf
wal_level = replica
archive_mode = on
archive_command = 'cp %p /path/to/archive/%f'

# Create base backup
pg_basebackup -D /path/to/backup -F tar -z -P
```

## Monitoring

### Key Metrics
```sql
-- Table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'streamsage'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Index usage
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'streamsage'
ORDER BY idx_scan DESC;

-- Slow queries
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    max_time
FROM pg_stat_statements
WHERE query LIKE '%streamsage%'
ORDER BY mean_time DESC
LIMIT 10;
```

### pg_stat_statements
```sql
-- Enable in postgresql.conf
shared_preload_libraries = 'pg_stat_statements'

-- Create extension
CREATE EXTENSION pg_stat_statements;
```

## Security

### Row-Level Security
```sql
-- Enable RLS on sensitive tables
ALTER TABLE streamsage.hub_transaction ENABLE ROW LEVEL SECURITY;

-- Create policy
CREATE POLICY user_access_policy ON streamsage.hub_transaction
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM streamsage.access_authorization aa
        WHERE aa.user_cnum = current_user
        AND aa.application_id = hub_transaction.application_id
        AND aa.is_active = 'Y'
    )
);
```

### SSL Connections
```bash
# postgresql.conf
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
ssl_ca_file = 'root.crt'
```

## Terminology Summary

### OP_TX_LINE_UID (Operation Transaction Line Unique ID)
- **Purpose**: Unique identifier for operations and their related transactions
- **Format**: Alphanumeric string (e.g., "25061815ABC123")
- **Usage**: Links parent operations with child transactions

### TX_LINE_GENERATE_INDC (Transaction Line Generation Indicator)
- **Values**: 'Y' or 'N'
- **'Y'**: This transaction generates its own TX_LINE (parent operation)
- **'N'**: This transaction uses parent's TX_LINE (child transaction)

### PARENT_OP_UID (Parent Operation UID)
- **Purpose**: Links child transactions to parent operation
- **Value**: Contains parent's `op_tx_line_uid` when `tx_line_generate_indc = 'N'`

## Best Practices

1. **Use JSONB over JSON** for better performance
2. **Create partial indexes** for frequently filtered queries
3. **Use EXPLAIN ANALYZE** before creating indexes
4. **Regular VACUUM and ANALYZE** for optimal performance
5. **Monitor pg_stat_statements** for slow queries
6. **Use connection pooling** (PgBouncer/pgpool)
7. **Enable query logging** for debugging
8. **Implement table partitioning** for large tables
9. **Use materialized views** for complex reports
10. **Regular backups** with pg_dump or pg_basebackup

## Support

### Resources
- PostgreSQL Documentation: https://www.postgresql.org/docs/
- Performance Tuning: https://wiki.postgresql.org/wiki/Performance_Optimization
- Monitoring Tools: pgAdmin, pg_stat_statements, pg_top

### Contact
For questions or issues, contact the StreamSage development team.

## Version History

### v2.0 (2026-03-06) - pg_02 Version
- Complete PostgreSQL conversion with updated terminology
- DNA → TX_LINE (Transaction Line)
- DEAL → OP (Operation)
- Schema: `streamsage`
- JSONB support for flexible configuration
- Enhanced indexing with partial and GIN indexes
- Trigger functions for automatic timestamp updates
- Optimized for PostgreSQL 12+

## License

Copyright © 2026. All rights reserved.