\set ON_ERROR_STOP on

BEGIN;
SET search_path TO tarot, public;

DO $$
DECLARE
  asset_id uuid;
  prompt_entity_id uuid;
  deck_id uuid;
  card_entity_id uuid;
  zodiac_term_id uuid;
BEGIN
  INSERT INTO media_assets (
    storage_key,
    byte_size,
    width_px,
    height_px,
    sha256,
    alt_text
  )
  VALUES (
    'prompts/test-lantern.jpg',
    1024,
    768,
    1024,
    repeat('a', 64),
    '测试灯笼'
  )
  RETURNING id INTO asset_id;

  BEGIN
    INSERT INTO media_assets (
      storage_key,
      byte_size,
      width_px,
      height_px,
      sha256
    )
    VALUES (
      'prompts/invalid-format.png',
      128,
      32,
      32,
      repeat('b', 64)
    );

    RAISE EXCEPTION 'non-JPG media was accepted';
  EXCEPTION
    WHEN check_violation THEN
      NULL;
  END;

  INSERT INTO catalog_entities (kind_code, slug, status)
  VALUES ('prompt_item', 'test-lantern', 'published')
  RETURNING id INTO prompt_entity_id;

  INSERT INTO prompt_items (
    entity_id,
    name,
    prompt_text,
    image_asset_id,
    tags
  )
  VALUES (
    prompt_entity_id,
    '灯笼',
    '你正在为谁照亮道路？',
    asset_id,
    ARRAY['光', '道路']
  );

  INSERT INTO tarot_decks (slug, name)
  VALUES ('test-deck', '测试牌组')
  RETURNING id INTO deck_id;

  BEGIN
    UPDATE catalog_entities
    SET kind_code = 'tarot_card'
    WHERE id = prompt_entity_id;

    RAISE EXCEPTION 'entity kind mutation was accepted';
  EXCEPTION
    WHEN check_violation THEN
      NULL;
  END;

  INSERT INTO catalog_entities (kind_code, slug, status)
  VALUES ('tarot_card', 'test-deck-fool', 'published')
  RETURNING id INTO card_entity_id;

  INSERT INTO tarot_cards (
    entity_id,
    deck_id,
    canonical_code,
    name,
    arcana_type,
    sequence_no,
    upright_keywords,
    image_asset_id
  )
  VALUES (
    card_entity_id,
    deck_id,
    'major-00',
    '愚者',
    'major',
    0,
    ARRAY['开始', '自由'],
    asset_id
  );

  SELECT term.id
  INTO zodiac_term_id
  FROM association_terms AS term
  JOIN association_taxonomies AS taxonomy
    ON taxonomy.id = term.taxonomy_id
  WHERE taxonomy.code = 'zodiac'
    AND term.code = 'aries';

  INSERT INTO entity_term_associations (
    entity_id,
    term_id,
    relation_code,
    weight,
    note
  )
  VALUES (
    card_entity_id,
    zodiac_term_id,
    'resonates_with',
    0.850,
    '测试关联'
  );

  IF (
    SELECT count(*)
    FROM entity_term_associations
    WHERE entity_id = card_entity_id
  ) <> 1 THEN
    RAISE EXCEPTION 'association smoke test failed';
  END IF;
END;
$$;

ROLLBACK;
