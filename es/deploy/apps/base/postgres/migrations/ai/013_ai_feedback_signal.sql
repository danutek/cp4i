-- =====================================================
-- StreamSage Enhanced Database Schema - AI Feedback Signals
-- Version: 2.0
-- Database: PostgreSQL
-- Description: User feedback for AI model improvement
-- Author: Dan Cogswell (danutek@us.ibm.com)
-- =====================================================

SET search_path TO streamsage;

-- =====================================================
-- AI FEEDBACK SIGNAL TABLE
-- Purpose: Captures user feedback on AI outputs for continuous model improvement
-- =====================================================

CREATE TABLE IF NOT EXISTS streamsage.ai_feedback_signal (
    ai_feedback_signal_uid        BIGSERIAL PRIMARY KEY,
    ai_recommendation_uid         BIGINT REFERENCES streamsage.ai_recommendation(ai_recommendation_uid),
    ai_observation_uid            BIGINT REFERENCES streamsage.ai_observation(ai_observation_uid),
    feedback_type_cd              VARCHAR(40) NOT NULL,
    feedback_value_cd             VARCHAR(40),
    feedback_score_num            NUMERIC(5,4),
    feedback_comment_txt          VARCHAR(4000),
    submitted_by_user_cnum        VARCHAR(10) REFERENCES streamsage.app_user(user_cnum),
    submitted_ts                  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_status_cd                 CHAR(1) NOT NULL DEFAULT 'A',
    CONSTRAINT chk_aifs_type CHECK (
        feedback_type_cd IN ('QUALITY','USEFULNESS','ACCURACY','OUTCOME','SAFETY')
    ),
    CONSTRAINT chk_aifs_row_status CHECK (row_status_cd IN ('A','I','D')),
    CONSTRAINT chk_aifs_target CHECK (
        ai_recommendation_uid IS NOT NULL OR ai_observation_uid IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS idx_ai_feedback_rec ON streamsage.ai_feedback_signal (ai_recommendation_uid, submitted_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_feedback_obs ON streamsage.ai_feedback_signal (ai_observation_uid, submitted_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_feedback_user ON streamsage.ai_feedback_signal (submitted_by_user_cnum, submitted_ts DESC);
CREATE INDEX IF NOT EXISTS idx_ai_feedback_type ON streamsage.ai_feedback_signal (feedback_type_cd, feedback_value_cd);

COMMENT ON TABLE streamsage.ai_feedback_signal IS 'User feedback on AI outputs for continuous model improvement and quality monitoring';
COMMENT ON COLUMN streamsage.ai_feedback_signal.feedback_type_cd IS 'Type of feedback: QUALITY (output quality), USEFULNESS (practical value), ACCURACY (correctness), OUTCOME (result effectiveness), SAFETY (risk assessment)';
COMMENT ON COLUMN streamsage.ai_feedback_signal.feedback_value_cd IS 'Categorized feedback value (e.g., POSITIVE, NEGATIVE, NEUTRAL, HELPFUL, NOT_HELPFUL)';
COMMENT ON COLUMN streamsage.ai_feedback_signal.feedback_score_num IS 'Numeric feedback score (e.g., 1-5 rating, 0.0-1.0 score)';
COMMENT ON COLUMN streamsage.ai_feedback_signal.feedback_comment_txt IS 'Free-text feedback comments from the user';