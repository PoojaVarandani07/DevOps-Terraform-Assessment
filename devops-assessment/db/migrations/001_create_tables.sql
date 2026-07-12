-- =============================================================================
-- Migration: 001_create_tables.sql
-- Creates the core schema for the hotel bookings platform.
-- This file is automatically executed by Docker Compose on first startup.
-- =============================================================================

-- Enable the uuid-ossp extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable pg_stat_statements for query performance analysis
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- =============================================================================
-- Table: hotel_bookings
-- Core booking record – one row per booking.
-- =============================================================================

CREATE TABLE IF NOT EXISTS hotel_bookings (
    id            UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id        UUID          NOT NULL,
    hotel_id      VARCHAR(100)  NOT NULL,
    city          VARCHAR(100)  NOT NULL,
    checkin_date  DATE          NOT NULL,
    checkout_date DATE          NOT NULL,
    amount        NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    status        VARCHAR(50)   NOT NULL
                      CHECK (status IN ('pending','confirmed','cancelled','completed','no_show')),
    created_at    TIMESTAMP     NOT NULL DEFAULT NOW(),

    -- Business rule: checkout must be after checkin
    CONSTRAINT chk_dates CHECK (checkout_date > checkin_date)
);

COMMENT ON TABLE  hotel_bookings              IS 'Core hotel booking records';
COMMENT ON COLUMN hotel_bookings.org_id       IS 'Organisation that made the booking';
COMMENT ON COLUMN hotel_bookings.hotel_id     IS 'External hotel identifier';
COMMENT ON COLUMN hotel_bookings.status       IS 'Booking lifecycle status';

-- =============================================================================
-- Table: booking_events
-- Append-only event log – every state change writes a new row.
-- =============================================================================

CREATE TABLE IF NOT EXISTS booking_events (
    id         BIGSERIAL     PRIMARY KEY,
    booking_id UUID          NOT NULL
                   REFERENCES hotel_bookings(id) ON DELETE CASCADE,
    event_type VARCHAR(100)  NOT NULL,
    payload    JSONB,
    created_at TIMESTAMP     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  booking_events             IS 'Immutable event log for booking lifecycle changes';
COMMENT ON COLUMN booking_events.event_type  IS 'Event name e.g. booking_created, status_changed, payment_received';
COMMENT ON COLUMN booking_events.payload     IS 'Arbitrary JSON context for the event';

-- =============================================================================
-- Indexes (see README.md § "Index Strategy" for full rationale)
-- =============================================================================

-- PRIMARY query optimisation target:
--   SELECT org_id, status, COUNT(*), SUM(amount)
--   FROM hotel_bookings
--   WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days'
--   GROUP BY org_id, status;
--
-- A composite index on (city, created_at) lets Postgres satisfy the WHERE
-- clause with an index range scan and avoid a full table sequential scan.
-- Including org_id and status as non-key columns makes the index covering,
-- so the aggregation can be resolved from the index alone (no heap access).
CREATE INDEX IF NOT EXISTS idx_bookings_city_created_at
    ON hotel_bookings (city, created_at DESC)
    INCLUDE (org_id, status, amount);

-- Support fast lookups by org + status (dashboards, admin queries)
CREATE INDEX IF NOT EXISTS idx_bookings_org_status
    ON hotel_bookings (org_id, status);

-- Support lookups by hotel (property management queries)
CREATE INDEX IF NOT EXISTS idx_bookings_hotel_id
    ON hotel_bookings (hotel_id);

-- Support event log lookups by booking_id (foreign-key join)
CREATE INDEX IF NOT EXISTS idx_events_booking_id
    ON booking_events (booking_id, created_at DESC);

-- Support filtering events by type (e.g. all payment_received events)
CREATE INDEX IF NOT EXISTS idx_events_event_type
    ON booking_events (event_type);
