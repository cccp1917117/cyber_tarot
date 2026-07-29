BEGIN;

CREATE SCHEMA IF NOT EXISTS tarot;
SET search_path TO tarot, public;

CREATE FUNCTION set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TABLE entity_kinds (
  code text PRIMARY KEY
    CHECK (code ~ '^[a-z][a-z0-9_]*$'),
  name text NOT NULL,
  description text,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO entity_kinds (code, name, description)
VALUES
  ('prompt_item', '提示物', '以 JPG 图片为核心的视觉提示物'),
  ('tarot_card', '塔罗牌', '某一套牌中的塔罗牌')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE catalog_entities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind_code text NOT NULL REFERENCES entity_kinds(code),
  slug text NOT NULL
    CHECK (slug ~ '^[a-z0-9]+(?:[a-z0-9_-]*[a-z0-9])?$'),
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'published', 'archived')),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX catalog_entities_slug_unique_ci
  ON catalog_entities (lower(slug));
CREATE INDEX catalog_entities_kind_status_idx
  ON catalog_entities (kind_code, status);
CREATE INDEX catalog_entities_metadata_gin_idx
  ON catalog_entities USING gin (metadata);

CREATE TRIGGER catalog_entities_set_updated_at
BEFORE UPDATE ON catalog_entities
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE FUNCTION prevent_entity_kind_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.kind_code IS DISTINCT FROM OLD.kind_code THEN
    RAISE EXCEPTION
      'entity kind cannot change from % to %',
      OLD.kind_code,
      NEW.kind_code
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER catalog_entities_prevent_kind_change
BEFORE UPDATE OF kind_code ON catalog_entities
FOR EACH ROW EXECUTE FUNCTION prevent_entity_kind_change();

CREATE TABLE media_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  storage_key text NOT NULL UNIQUE
    CHECK (storage_key !~ '(^|/)\.\.?(/|$)')
    CHECK (storage_key ~* '\.(jpg|jpeg)$'),
  mime_type text NOT NULL DEFAULT 'image/jpeg'
    CHECK (mime_type = 'image/jpeg'),
  byte_size bigint NOT NULL CHECK (byte_size > 0),
  width_px integer NOT NULL CHECK (width_px > 0),
  height_px integer NOT NULL CHECK (height_px > 0),
  sha256 char(64) NOT NULL UNIQUE
    CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  alt_text text,
  attribution text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX media_assets_metadata_gin_idx
  ON media_assets USING gin (metadata);

CREATE TRIGGER media_assets_set_updated_at
BEFORE UPDATE ON media_assets
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE FUNCTION enforce_entity_kind()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  actual_kind text;
BEGIN
  SELECT kind_code
  INTO actual_kind
  FROM catalog_entities
  WHERE id = NEW.entity_id;

  IF actual_kind IS DISTINCT FROM TG_ARGV[0] THEN
    RAISE EXCEPTION
      'entity % has kind %, expected %',
      NEW.entity_id,
      coalesce(actual_kind, '<missing>'),
      TG_ARGV[0]
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TABLE prompt_items (
  entity_id uuid PRIMARY KEY
    REFERENCES catalog_entities(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  prompt_text text,
  description text,
  image_asset_id uuid NOT NULL
    REFERENCES media_assets(id) ON DELETE RESTRICT,
  tags text[] NOT NULL DEFAULT '{}',
  source text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX prompt_items_image_asset_idx
  ON prompt_items (image_asset_id);
CREATE INDEX prompt_items_tags_gin_idx
  ON prompt_items USING gin (tags);

CREATE TRIGGER prompt_items_enforce_kind
BEFORE INSERT OR UPDATE OF entity_id ON prompt_items
FOR EACH ROW EXECUTE FUNCTION enforce_entity_kind('prompt_item');

CREATE TRIGGER prompt_items_set_updated_at
BEFORE UPDATE ON prompt_items
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE tarot_decks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL
    CHECK (slug ~ '^[a-z0-9]+(?:[a-z0-9_-]*[a-z0-9])?$'),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  description text,
  author text,
  publisher text,
  published_year smallint
    CHECK (published_year BETWEEN 1400 AND 9999),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX tarot_decks_slug_unique_ci
  ON tarot_decks (lower(slug));
CREATE INDEX tarot_decks_metadata_gin_idx
  ON tarot_decks USING gin (metadata);

CREATE TRIGGER tarot_decks_set_updated_at
BEFORE UPDATE ON tarot_decks
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE tarot_cards (
  entity_id uuid PRIMARY KEY
    REFERENCES catalog_entities(id) ON DELETE CASCADE,
  deck_id uuid NOT NULL
    REFERENCES tarot_decks(id) ON DELETE CASCADE,
  canonical_code text NOT NULL
    CHECK (canonical_code ~ '^[a-z0-9]+(?:[a-z0-9_-]*[a-z0-9])?$'),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  arcana_type text NOT NULL
    CHECK (arcana_type IN ('major', 'minor', 'custom')),
  suit_code text,
  rank_code text,
  sequence_no smallint CHECK (sequence_no >= 0),
  upright_keywords text[] NOT NULL DEFAULT '{}',
  reversed_keywords text[] NOT NULL DEFAULT '{}',
  upright_meaning text,
  reversed_meaning text,
  description text,
  image_asset_id uuid NOT NULL
    REFERENCES media_assets(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tarot_cards_deck_code_unique
    UNIQUE (deck_id, canonical_code),
  CONSTRAINT tarot_cards_minor_suit_required
    CHECK (arcana_type <> 'minor' OR suit_code IS NOT NULL)
);

CREATE INDEX tarot_cards_deck_sequence_idx
  ON tarot_cards (deck_id, sequence_no);
CREATE INDEX tarot_cards_image_asset_idx
  ON tarot_cards (image_asset_id);
CREATE INDEX tarot_cards_upright_keywords_gin_idx
  ON tarot_cards USING gin (upright_keywords);
CREATE INDEX tarot_cards_reversed_keywords_gin_idx
  ON tarot_cards USING gin (reversed_keywords);

CREATE TRIGGER tarot_cards_enforce_kind
BEFORE INSERT OR UPDATE OF entity_id ON tarot_cards
FOR EACH ROW EXECUTE FUNCTION enforce_entity_kind('tarot_card');

CREATE TRIGGER tarot_cards_set_updated_at
BEFORE UPDATE ON tarot_cards
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE association_taxonomies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE
    CHECK (code ~ '^[a-z][a-z0-9_]*$'),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  description text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX association_taxonomies_metadata_gin_idx
  ON association_taxonomies USING gin (metadata);

CREATE TRIGGER association_taxonomies_set_updated_at
BEFORE UPDATE ON association_taxonomies
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE association_terms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  taxonomy_id uuid NOT NULL
    REFERENCES association_taxonomies(id) ON DELETE CASCADE,
  code text NOT NULL
    CHECK (code ~ '^[a-z0-9]+(?:[a-z0-9_-]*[a-z0-9])?$'),
  label text NOT NULL CHECK (length(btrim(label)) > 0),
  description text,
  sort_order integer NOT NULL DEFAULT 0,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT association_terms_taxonomy_code_unique
    UNIQUE (taxonomy_id, code)
);

CREATE INDEX association_terms_taxonomy_sort_idx
  ON association_terms (taxonomy_id, sort_order, code);
CREATE INDEX association_terms_metadata_gin_idx
  ON association_terms USING gin (metadata);

CREATE TRIGGER association_terms_set_updated_at
BEFORE UPDATE ON association_terms
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE entity_term_associations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL
    REFERENCES catalog_entities(id) ON DELETE CASCADE,
  term_id uuid NOT NULL
    REFERENCES association_terms(id) ON DELETE CASCADE,
  relation_code text NOT NULL DEFAULT 'associated_with'
    CHECK (relation_code ~ '^[a-z][a-z0-9_]*$'),
  weight numeric(4, 3) NOT NULL DEFAULT 1.000
    CHECK (weight BETWEEN 0.000 AND 1.000),
  note text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT entity_term_associations_unique
    UNIQUE (entity_id, term_id, relation_code)
);

CREATE INDEX entity_term_associations_entity_idx
  ON entity_term_associations (entity_id, relation_code);
CREATE INDEX entity_term_associations_term_idx
  ON entity_term_associations (term_id, relation_code);
CREATE INDEX entity_term_associations_metadata_gin_idx
  ON entity_term_associations USING gin (metadata);

CREATE TRIGGER entity_term_associations_set_updated_at
BEFORE UPDATE ON entity_term_associations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMIT;
