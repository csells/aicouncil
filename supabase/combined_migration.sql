-- =============================================================================
-- COMBINED MIGRATION FOR LLM COUNCIL
-- Run this entire file in Supabase SQL Editor
-- Dashboard: https://supabase.com/dashboard/project/sctfvvhiiplllwrhcnku/sql
-- =============================================================================

-- Part 1: Base Schema
-- ============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Sessions table (conversations)
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT DEFAULT 'New Conversation',
    council_type TEXT DEFAULT 'general',
    council_mode TEXT DEFAULT 'synthesized',
    models JSONB,  -- JSON array of model IDs
    chairman_model TEXT,
    roles_enabled BOOLEAN DEFAULT FALSE,
    enhancements JSONB,  -- JSON array
    tags JSONB,  -- JSON array
    is_archived BOOLEAN DEFAULT FALSE,  -- Archive flag to hide old conversations
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Migration: Add is_archived column if it doesn't exist (for existing databases)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'sessions' AND column_name = 'is_archived'
    ) THEN
        ALTER TABLE sessions ADD COLUMN is_archived BOOLEAN DEFAULT FALSE;
    END IF;
END $$;

-- Messages table
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    role TEXT NOT NULL,  -- user, assistant, system
    content TEXT,
    model_name TEXT,
    specialist_role TEXT,
    confidence_score REAL,
    debate_round INTEGER,
    stage_data JSONB,  -- JSON for stage1/stage2/stage3 data
    metadata JSONB,  -- JSON for additional metadata
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Model presets table
CREATE TABLE IF NOT EXISTS model_presets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    models JSONB NOT NULL,  -- JSON array of model IDs
    chairman_model TEXT,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Predictions table for tracking advice accuracy
CREATE TABLE IF NOT EXISTS predictions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    prediction_text TEXT NOT NULL,
    model_name TEXT,
    category TEXT,  -- business, personal, technical, etc.
    outcome TEXT,  -- NULL until recorded
    outcome_notes TEXT,
    accuracy_score REAL,  -- 0-1 scale
    predicted_at TIMESTAMPTZ DEFAULT NOW(),
    outcome_recorded_at TIMESTAMPTZ
);

-- Conversation state for multi-round modes (debate, socratic)
CREATE TABLE IF NOT EXISTS conversation_state (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE UNIQUE,
    mode TEXT NOT NULL,
    query TEXT NOT NULL,
    rounds JSONB,  -- Array of round responses
    current_round INTEGER DEFAULT 1,
    models JSONB,
    chairman_model TEXT,
    council_type TEXT,
    roles_enabled BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id);
CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at);
CREATE INDEX IF NOT EXISTS idx_sessions_created ON sessions(created_at);
CREATE INDEX IF NOT EXISTS idx_sessions_updated ON sessions(updated_at);
CREATE INDEX IF NOT EXISTS idx_predictions_session ON predictions(session_id);
CREATE INDEX IF NOT EXISTS idx_conversation_state_session ON conversation_state(session_id);

-- Full-text search index on messages
CREATE INDEX IF NOT EXISTS idx_messages_content_search ON messages USING GIN (to_tsvector('english', COALESCE(content, '')));

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for updated_at
DROP TRIGGER IF EXISTS update_sessions_updated_at ON sessions;
CREATE TRIGGER update_sessions_updated_at
    BEFORE UPDATE ON sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_conversation_state_updated_at ON conversation_state;
CREATE TRIGGER update_conversation_state_updated_at
    BEFORE UPDATE ON conversation_state
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Insert default model preset
INSERT INTO model_presets (name, description, models, chairman_model, is_default)
VALUES (
    'Frontier Models',
    'Latest frontier models from major providers',
    '["openai/gpt-5.2", "anthropic/claude-opus-4.5", "google/gemini-3-pro-preview", "x-ai/grok-4"]',
    'anthropic/claude-opus-4.5',
    TRUE
) ON CONFLICT (name) DO NOTHING;

-- Row Level Security (RLS) - Enable for all tables
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE model_presets ENABLE ROW LEVEL SECURITY;
ALTER TABLE predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_state ENABLE ROW LEVEL SECURITY;

-- RLS Policies - Allow all operations for authenticated service role
-- These policies allow the backend (using service_role key) full access
CREATE POLICY "Service role has full access to sessions" ON sessions
    FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Service role has full access to messages" ON messages
    FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Service role has full access to model_presets" ON model_presets
    FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Service role has full access to predictions" ON predictions
    FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Service role has full access to conversation_state" ON conversation_state
    FOR ALL USING (true) WITH CHECK (true);

-- Part 2: User Authentication Migration
-- =============================================================================

-- Add user_id to sessions
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

-- Add user_id to model_presets
ALTER TABLE model_presets ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

-- Add user_id to predictions
ALTER TABLE predictions ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

-- Create indexes for user_id columns
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_model_presets_user ON model_presets(user_id);
CREATE INDEX IF NOT EXISTS idx_predictions_user ON predictions(user_id);

-- Drop old "allow all" policies
DROP POLICY IF EXISTS "Service role has full access to sessions" ON sessions;
DROP POLICY IF EXISTS "Service role has full access to messages" ON messages;
DROP POLICY IF EXISTS "Service role has full access to model_presets" ON model_presets;
DROP POLICY IF EXISTS "Service role has full access to predictions" ON predictions;
DROP POLICY IF EXISTS "Service role has full access to conversation_state" ON conversation_state;

-- Sessions: Users can only access their own sessions
CREATE POLICY "Users can view own sessions" ON sessions
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create own sessions" ON sessions
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own sessions" ON sessions
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own sessions" ON sessions
    FOR DELETE USING (auth.uid() = user_id);

-- Messages: Users can access messages in their sessions
CREATE POLICY "Users can view messages in own sessions" ON messages
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM sessions WHERE sessions.id = messages.session_id AND sessions.user_id = auth.uid())
    );

CREATE POLICY "Users can create messages in own sessions" ON messages
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM sessions WHERE sessions.id = messages.session_id AND sessions.user_id = auth.uid())
    );

CREATE POLICY "Users can update messages in own sessions" ON messages
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM sessions WHERE sessions.id = messages.session_id AND sessions.user_id = auth.uid())
    );

CREATE POLICY "Users can delete messages in own sessions" ON messages
    FOR DELETE USING (
        EXISTS (SELECT 1 FROM sessions WHERE sessions.id = messages.session_id AND sessions.user_id = auth.uid())
    );

-- Model presets: Users see default presets + their own
CREATE POLICY "Users can view default and own presets" ON model_presets
    FOR SELECT USING (is_default = TRUE OR auth.uid() = user_id);

CREATE POLICY "Users can create own presets" ON model_presets
    FOR INSERT WITH CHECK (auth.uid() = user_id AND is_default = FALSE);

CREATE POLICY "Users can update own presets" ON model_presets
    FOR UPDATE USING (auth.uid() = user_id AND is_default = FALSE);

CREATE POLICY "Users can delete own presets" ON model_presets
    FOR DELETE USING (auth.uid() = user_id AND is_default = FALSE);

-- Predictions: Users can only access their own predictions
CREATE POLICY "Users can view own predictions" ON predictions
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create own predictions" ON predictions
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own predictions" ON predictions
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own predictions" ON predictions
    FOR DELETE USING (auth.uid() = user_id);

-- Conversation state: Users can access state for their sessions
CREATE POLICY "Users can view own conversation state" ON conversation_state
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM sessions WHERE sessions.id = conversation_state.session_id AND sessions.user_id = auth.uid())
    );

CREATE POLICY "Users can create own conversation state" ON conversation_state
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM sessions WHERE sessions.id = conversation_state.session_id AND sessions.user_id = auth.uid())
    );

CREATE POLICY "Users can update own conversation state" ON conversation_state
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM sessions WHERE sessions.id = conversation_state.session_id AND sessions.user_id = auth.uid())
    );

CREATE POLICY "Users can delete own conversation state" ON conversation_state
    FOR DELETE USING (
        EXISTS (SELECT 1 FROM sessions WHERE sessions.id = conversation_state.session_id AND sessions.user_id = auth.uid())
    );

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
-- Tables created: sessions, messages, model_presets, predictions, conversation_state
-- RLS policies configured for per-user data isolation
-- Default model preset inserted
-- =============================================================================
