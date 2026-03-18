-- ============================================================
-- Supabase PostgreSQL Schema for Maps Saved Companion App
-- Run this in Supabase SQL Editor
-- ============================================================

-- Enable UUID extension (usually already enabled)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── places ──
CREATE TABLE places (
  id TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source_key TEXT NOT NULL,
  source_title TEXT,
  maps_url TEXT,
  note TEXT,
  comments TEXT,
  collection_name TEXT,
  collection_description TEXT,
  raw_payload_json TEXT,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  last_seen_at TIMESTAMPTZ NOT NULL,
  is_hidden BOOLEAN NOT NULL DEFAULT FALSE,
  is_deleted_candidate BOOLEAN NOT NULL DEFAULT FALSE,
  deleted_miss_count INTEGER NOT NULL DEFAULT 0,
  manual_group_override BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (user_id, source_key)
);

CREATE INDEX idx_places_user_id ON places(user_id);
CREATE INDEX idx_places_source_key ON places(user_id, source_key);
CREATE INDEX idx_places_last_seen_at ON places(user_id, last_seen_at);
CREATE INDEX idx_places_hidden ON places(user_id, is_hidden);

-- ── groups ──
CREATE TABLE groups (
  id TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  icon_name TEXT NOT NULL,
  color_key TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  system_group BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (user_id, name)
);

CREATE INDEX idx_groups_user_id ON groups(user_id);

-- ── place_groups ──
CREATE TABLE place_groups (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  place_id TEXT NOT NULL,
  group_id TEXT NOT NULL,
  source TEXT NOT NULL,
  confidence DOUBLE PRECISION NOT NULL DEFAULT 1.0,
  created_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (user_id, place_id, group_id, source),
  FOREIGN KEY (place_id) REFERENCES places(id) ON DELETE CASCADE,
  FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE
);

CREATE INDEX idx_place_groups_group_id ON place_groups(user_id, group_id);

-- ── sync_jobs ──
CREATE TABLE sync_jobs (
  id TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  archive_identifier TEXT NOT NULL,
  archive_name TEXT NOT NULL,
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ,
  status TEXT NOT NULL,
  new_count INTEGER NOT NULL DEFAULT 0,
  updated_count INTEGER NOT NULL DEFAULT 0,
  unchanged_count INTEGER NOT NULL DEFAULT 0,
  deleted_candidate_count INTEGER NOT NULL DEFAULT 0,
  skipped_row_count INTEGER NOT NULL DEFAULT 0,
  error_message TEXT
);

CREATE INDEX idx_sync_jobs_user_id ON sync_jobs(user_id);
CREATE INDEX idx_sync_jobs_started_at ON sync_jobs(user_id, started_at);

-- ── classification_rules ──
CREATE TABLE classification_rules (
  id TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  group_id TEXT NOT NULL,
  pattern TEXT NOT NULL,
  target_fields TEXT NOT NULL,
  is_regex BOOLEAN NOT NULL DEFAULT FALSE,
  priority INTEGER NOT NULL DEFAULT 100,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE
);

CREATE INDEX idx_classification_rules_user_id ON classification_rules(user_id);

-- ============================================================
-- RLS Policies
-- ============================================================

ALTER TABLE places ENABLE ROW LEVEL SECURITY;
ALTER TABLE groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE place_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE classification_rules ENABLE ROW LEVEL SECURITY;

-- places
CREATE POLICY "Users can only access own places"
  ON places FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- groups
CREATE POLICY "Users can only access own groups"
  ON groups FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- place_groups
CREATE POLICY "Users can only access own place_groups"
  ON place_groups FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- sync_jobs
CREATE POLICY "Users can only access own sync_jobs"
  ON sync_jobs FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- classification_rules
CREATE POLICY "Users can only access own classification_rules"
  ON classification_rules FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- RPC Functions
-- ============================================================

-- replace_auto_groups: atomic delete non-manual + insert new
CREATE OR REPLACE FUNCTION replace_auto_groups(
  p_user_id UUID,
  p_place_id TEXT,
  p_new_groups JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Verify caller owns the data
  IF p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Delete existing auto groups (keep manual)
  DELETE FROM place_groups
  WHERE user_id = p_user_id
    AND place_id = p_place_id
    AND source != 'manual';

  -- Insert new groups
  INSERT INTO place_groups (user_id, place_id, group_id, source, confidence, created_at)
  SELECT
    (g->>'user_id')::UUID,
    g->>'place_id',
    g->>'group_id',
    g->>'source',
    (g->>'confidence')::DOUBLE PRECISION,
    (g->>'created_at')::TIMESTAMPTZ
  FROM jsonb_array_elements(p_new_groups) AS g;
END;
$$;

-- seed_user_data: called on first login to populate default groups + rules
CREATE OR REPLACE FUNCTION seed_user_data()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_group_count INTEGER;
  v_g_spring TEXT := gen_random_uuid()::TEXT;
  v_g_summer TEXT := gen_random_uuid()::TEXT;
  v_g_autumn TEXT := gen_random_uuid()::TEXT;
  v_g_winter TEXT := gen_random_uuid()::TEXT;
  v_g_sakura TEXT := gen_random_uuid()::TEXT;
  v_g_food   TEXT := gen_random_uuid()::TEXT;
  v_g_stars  TEXT := gen_random_uuid()::TEXT;
  v_g_family TEXT := gen_random_uuid()::TEXT;
  v_g_uncat  TEXT := gen_random_uuid()::TEXT;
BEGIN
  -- Check if user already has data
  SELECT COUNT(*) INTO v_group_count FROM groups WHERE user_id = v_user_id;
  IF v_group_count > 0 THEN
    RETURN;
  END IF;

  -- Insert default groups
  INSERT INTO groups (id, user_id, name, icon_name, color_key, sort_order, system_group) VALUES
    (v_g_spring, v_user_id, '春',       'flower',         'pink',       1,  FALSE),
    (v_g_summer, v_user_id, '夏',       'sunny',          'orange',     2,  FALSE),
    (v_g_autumn, v_user_id, '秋',       'leaf',           'red',        3,  FALSE),
    (v_g_winter, v_user_id, '冬',       'snow',           'blue',       4,  FALSE),
    (v_g_sakura, v_user_id, '桜スポット', 'cherry_blossom', 'pink_light', 5,  FALSE),
    (v_g_food,   v_user_id, '飲食店',    'restaurant',     'amber',      6,  FALSE),
    (v_g_stars,  v_user_id, '星景',      'star',           'indigo',     7,  FALSE),
    (v_g_family, v_user_id, '家族向け',   'family',         'green',      8,  FALSE),
    (v_g_uncat,  v_user_id, '未分類',    'help_outline',   'grey',       99, TRUE);

  -- Insert default classification rules
  INSERT INTO classification_rules (id, user_id, group_id, pattern, target_fields, is_regex, priority, enabled) VALUES
    (gen_random_uuid()::TEXT, v_user_id, v_g_spring, '桜|花見|さくら|菜の花|春',             'title,note,comments,collectionName', FALSE, 10, TRUE),
    (gen_random_uuid()::TEXT, v_user_id, v_g_sakura, '桜|花見|さくら',                       'title,note,comments',                FALSE, 10, TRUE),
    (gen_random_uuid()::TEXT, v_user_id, v_g_food,   '飲食店|ランチ|ディナー|カフェ|喫茶|レストラン', 'title,note,comments,collectionName', FALSE, 20, TRUE),
    (gen_random_uuid()::TEXT, v_user_id, v_g_stars,  '星|星空|天の川|夜景',                   'title,note,comments',                FALSE, 20, TRUE),
    (gen_random_uuid()::TEXT, v_user_id, v_g_autumn, '紅葉|もみじ|いちょう|秋',               'title,note,comments',                FALSE, 20, TRUE),
    (gen_random_uuid()::TEXT, v_user_id, v_g_summer, '海|花火|ひまわり|川|夏',                 'title,note,comments',                FALSE, 20, TRUE),
    (gen_random_uuid()::TEXT, v_user_id, v_g_winter, '雪|イルミ|クリスマス|温泉|冬',            'title,note,comments',                FALSE, 20, TRUE),
    (gen_random_uuid()::TEXT, v_user_id, v_g_family, '公園|遊園地|動物園|水族館|キッズ|子供|家族',  'title,note,comments,collectionName', FALSE, 30, TRUE);
END;
$$;
