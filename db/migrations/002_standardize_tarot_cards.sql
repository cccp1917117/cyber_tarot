BEGIN;

SET search_path TO tarot, public;

CREATE TABLE tarot_archetypes (
  code text PRIMARY KEY
    CHECK (code ~ '^[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?$'),
  system_code text NOT NULL DEFAULT 'rws-78'
    CHECK (system_code ~ '^[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?$'),
  name_zh text NOT NULL CHECK (length(btrim(name_zh)) > 0),
  name_en text NOT NULL CHECK (length(btrim(name_en)) > 0),
  arcana_type text NOT NULL
    CHECK (arcana_type IN ('major', 'minor', 'custom')),
  major_number smallint,
  suit_code text,
  rank_code text,
  rank_order smallint,
  sequence_no smallint NOT NULL CHECK (sequence_no >= 0),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tarot_archetypes_structure_check
    CHECK (
      (
        arcana_type = 'major'
        AND major_number BETWEEN 0 AND 21
        AND suit_code IS NULL
        AND rank_code IS NULL
        AND rank_order IS NULL
      )
      OR (
        arcana_type = 'minor'
        AND major_number IS NULL
        AND suit_code IS NOT NULL
        AND rank_code IS NOT NULL
        AND rank_order BETWEEN 1 AND 14
      )
      OR arcana_type = 'custom'
    ),
  CONSTRAINT tarot_archetypes_rws_structure_check
    CHECK (
      system_code <> 'rws-78'
      OR (
        (
          arcana_type = 'major'
          AND code = 'major-' || lpad(major_number::text, 2, '0')
        )
        OR (
          arcana_type = 'minor'
          AND suit_code IN ('wands', 'cups', 'swords', 'pentacles')
          AND rank_code IN (
            'ace',
            'two',
            'three',
            'four',
            'five',
            'six',
            'seven',
            'eight',
            'nine',
            'ten',
            'page',
            'knight',
            'queen',
            'king'
          )
          AND code = 'minor-' || suit_code || '-' || rank_code
        )
      )
    )
);

CREATE UNIQUE INDEX tarot_archetypes_system_sequence_unique
  ON tarot_archetypes (system_code, sequence_no);
CREATE UNIQUE INDEX tarot_archetypes_major_identity_unique
  ON tarot_archetypes (system_code, major_number)
  WHERE arcana_type = 'major';
CREATE UNIQUE INDEX tarot_archetypes_minor_identity_unique
  ON tarot_archetypes (system_code, suit_code, rank_code)
  WHERE arcana_type = 'minor';
CREATE INDEX tarot_archetypes_structure_idx
  ON tarot_archetypes (system_code, arcana_type, suit_code, rank_order);
CREATE INDEX tarot_archetypes_metadata_gin_idx
  ON tarot_archetypes USING gin (metadata);

CREATE TRIGGER tarot_archetypes_set_updated_at
BEFORE UPDATE ON tarot_archetypes
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE tarot_cards
  RENAME COLUMN canonical_code TO card_code;

ALTER TABLE tarot_cards
  ADD COLUMN archetype_code text
    REFERENCES tarot_archetypes(code) ON DELETE RESTRICT;

ALTER TABLE tarot_cards
  ADD CONSTRAINT tarot_cards_standard_archetype_required
  CHECK (arcana_type = 'custom' OR archetype_code IS NOT NULL)
  NOT VALID;

ALTER TABLE tarot_cards
  ADD CONSTRAINT tarot_cards_custom_code_check
  CHECK (arcana_type <> 'custom' OR card_code LIKE 'custom-%')
  NOT VALID;

CREATE UNIQUE INDEX tarot_cards_deck_archetype_unique
  ON tarot_cards (deck_id, archetype_code)
  WHERE archetype_code IS NOT NULL;

CREATE FUNCTION normalize_tarot_card()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  archetype tarot_archetypes%ROWTYPE;
BEGIN
  IF NEW.archetype_code IS NULL THEN
    IF NEW.arcana_type IS DISTINCT FROM 'custom' THEN
      RAISE EXCEPTION
        'standard tarot card requires archetype_code'
        USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
  END IF;

  SELECT *
  INTO archetype
  FROM tarot_archetypes
  WHERE code = NEW.archetype_code;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'tarot archetype % does not exist',
      NEW.archetype_code
      USING ERRCODE = '23503';
  END IF;

  IF NEW.card_code IS NULL THEN
    NEW.card_code = archetype.code;
  ELSIF NEW.card_code IS DISTINCT FROM archetype.code THEN
    RAISE EXCEPTION
      'standard card_code % must equal archetype_code %',
      NEW.card_code,
      archetype.code
      USING ERRCODE = '23514';
  END IF;

  IF NEW.arcana_type IS NOT NULL
     AND NEW.arcana_type IS DISTINCT FROM archetype.arcana_type THEN
    RAISE EXCEPTION
      'arcana_type % conflicts with archetype %',
      NEW.arcana_type,
      archetype.code
      USING ERRCODE = '23514';
  END IF;

  IF NEW.suit_code IS NOT NULL
     AND NEW.suit_code IS DISTINCT FROM archetype.suit_code THEN
    RAISE EXCEPTION
      'suit_code % conflicts with archetype %',
      NEW.suit_code,
      archetype.code
      USING ERRCODE = '23514';
  END IF;

  IF NEW.rank_code IS NOT NULL
     AND NEW.rank_code IS DISTINCT FROM archetype.rank_code THEN
    RAISE EXCEPTION
      'rank_code % conflicts with archetype %',
      NEW.rank_code,
      archetype.code
      USING ERRCODE = '23514';
  END IF;

  IF NEW.sequence_no IS NOT NULL
     AND NEW.sequence_no IS DISTINCT FROM archetype.sequence_no THEN
    RAISE EXCEPTION
      'sequence_no % conflicts with archetype %',
      NEW.sequence_no,
      archetype.code
      USING ERRCODE = '23514';
  END IF;

  NEW.arcana_type = archetype.arcana_type;
  NEW.suit_code = archetype.suit_code;
  NEW.rank_code = archetype.rank_code;
  NEW.sequence_no = archetype.sequence_no;

  RETURN NEW;
END;
$$;

CREATE TRIGGER tarot_cards_normalize_structure
BEFORE INSERT OR UPDATE OF
  card_code,
  archetype_code,
  arcana_type,
  suit_code,
  rank_code,
  sequence_no
ON tarot_cards
FOR EACH ROW EXECUTE FUNCTION normalize_tarot_card();

COMMENT ON TABLE tarot_archetypes IS
  '跨套牌复用的塔罗原型；rws-78 使用固定的 78 张标准牌码。';
COMMENT ON COLUMN tarot_cards.card_code IS
  '套牌内稳定牌码；标准牌必须与 archetype_code 相同。';
COMMENT ON COLUMN tarot_cards.archetype_code IS
  '标准原型引用；仅 custom 类型可以为空。';

COMMIT;
