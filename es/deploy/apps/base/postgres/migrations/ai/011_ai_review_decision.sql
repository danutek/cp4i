-- =====================================================
-- StreamSage Enhanced Database Schema - AI Review Decisions
-- Version: 2.0
-- Database: PostgreSQL
-- Description: Human review decisions for AI recommendations
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- AI REVIEW DECISION TABLE
-- Purpose: Captures human review decisions on AI recommendations and actions
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.ai_review_decision (
    ai_review_decision_uid        BIGSERIAL PRIMARY KEY,
    ai_recommendation_uid         BIGINT REFERENCES streamsage.ai_recommendation(ai_recommendation_uid),
    ai_recommendation_action_uid  BIGINT REFERENCES streamsage.ai_recommendation_action(ai_recommendation_action_uid),
    review_decision_cd            VARCHAR(20) NOT NULL,
    review_reason_cd              VARCHAR(40),
    review_comment_txt            VARCHAR(4000),
    reviewed_by_user_cnum         VARCHAR(10) REFERENCES streamsage.app_user(user_cnum),
    reviewed_by_actor_id          VARCHAR(100),
    reviewed_ts                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    create_id                     VARCHAR(60) NOT NULL,
    create_ts                     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd                 CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT chk_aird_decision CHECK (
        review_decision_cd IN ('ACCEPT','REJECT','REQUEST_CHANGES','DEFER','CANCEL')
    ),
    CONSTRAINT chk_aird_row_status CHECK (row_status_cd IN ('A','I','D')),
    CONSTRAINT chk_aird_target CHECK (
        ai_recommendation_uid IS NOT NULL OR ai_recommendation_action_uid IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS idx_ai_review_rec ON streamsage.ai_review_decision (ai_recommendation_uid, reviewed_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_review_action ON streamsage.ai_review_decision (ai_recommendation_action_uid, reviewed_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_review_user ON streamsage.ai_review_decision (reviewed_by_user_cnum, reviewed_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_review_decision ON streamsage.ai_review_decision (review_decision_cd, reviewed_ts DESC);

COMMENT ON TABLE streamsage.ai_review_decision IS 'Human review decisions on AI recommendations and actions with rationale and comments';
COMMENT ON COLUMN streamsage.ai_review_decision.review_decision_cd IS 'Decision: ACCEPT (approve), REJECT (deny), REQUEST_CHANGES (needs modification), DEFER (postpone), CANCEL (withdraw)';
COMMENT ON COLUMN streamsage.ai_review_decision.review_reason_cd IS 'Categorized reason for the decision';
COMMENT ON COLUMN streamsage.ai_review_decision.reviewed_by_user_cnum IS 'User who made the review decision';
COMMENT ON COLUMN streamsage.ai_review_decision.reviewed_by_actor_id IS 'Actor identifier (may be different from user for delegated reviews)';