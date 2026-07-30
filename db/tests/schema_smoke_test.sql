\set ON_ERROR_STOP on

BEGIN;
SET search_path TO tarot, public;

DO $$
DECLARE
  asset_id uuid;
  prompt_entity_id uuid;
  deck_id uuid;
  card_entity_id uuid;
  back_asset_id uuid;
  zodiac_term_id uuid;
  selected_method_id uuid;
  created_session_id uuid;
  selected_theme_position_id uuid;
  selected_insight_position_id uuid;
BEGIN
  IF (
    SELECT count(*)
    FROM tarot_archetypes
    WHERE system_code = 'rws-78'
  ) <> 78 THEN
    RAISE EXCEPTION 'RWS archetype seed must contain 78 cards';
  END IF;

  IF (
    SELECT count(*)
    FROM divination_methods
    WHERE status = 'active'
  ) <> 5 THEN
    RAISE EXCEPTION 'divination seed must contain 5 active methods';
  END IF;

  IF (
    SELECT count(*)
    FROM divination_method_positions
  ) <> 11 THEN
    RAISE EXCEPTION 'divination seed must contain 11 positions';
  END IF;

  INSERT INTO media_assets (
    storage_key,
    byte_size,
    width_px,
    height_px,
    sha256,
    alt_text
  )
  VALUES (
    'prompts/test-lantern.png',
    1024,
    768,
    1024,
    repeat('a', 64),
    '测试灯笼'
  )
  RETURNING id INTO asset_id;

  INSERT INTO media_assets (
    storage_key,
    byte_size,
    width_px,
    height_px,
    sha256,
    alt_text
  )
  VALUES (
    'tarot/test-deck/card-back.png',
    512,
    1200,
    1800,
    repeat('c', 64),
    '测试牌组卡背'
  )
  RETURNING id INTO back_asset_id;

  BEGIN
    INSERT INTO media_assets (
      storage_key,
      byte_size,
      width_px,
      height_px,
      sha256
    )
    VALUES (
      'prompts/invalid-format.jpg',
      128,
      32,
      32,
      repeat('b', 64)
    );

    RAISE EXCEPTION 'non-PNG media was accepted';
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

  INSERT INTO tarot_decks (
    slug,
    name,
    back_image_asset_id,
    back_is_reversible
  )
  VALUES (
    'test-deck',
    '测试牌组',
    back_asset_id,
    true
  )
  RETURNING id INTO deck_id;

  BEGIN
    INSERT INTO tarot_decks (slug, name)
    VALUES ('missing-back-deck', '缺少卡背的牌组');

    RAISE EXCEPTION 'deck without card back was accepted';
  EXCEPTION
    WHEN check_violation THEN
      NULL;
  END;

  BEGIN
    INSERT INTO tarot_decks (
      slug,
      name,
      back_image_asset_id
    )
    VALUES (
      'duplicate-back-deck',
      '重复卡背的牌组',
      back_asset_id
    );

    RAISE EXCEPTION 'duplicate deck back asset was accepted';
  EXCEPTION
    WHEN unique_violation THEN
      NULL;
  END;

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
    card_code,
    archetype_code,
    name,
    upright_keywords,
    image_asset_id
  )
  VALUES (
    card_entity_id,
    deck_id,
    'major-00',
    'major-00',
    '愚者',
    ARRAY['开始', '自由'],
    asset_id
  );

  IF NOT EXISTS (
    SELECT 1
    FROM tarot_cards
    WHERE entity_id = card_entity_id
      AND arcana_type = 'major'
      AND sequence_no = 0
      AND suit_code IS NULL
      AND rank_code IS NULL
  ) THEN
    RAISE EXCEPTION 'tarot archetype normalization failed';
  END IF;

  SELECT id
  INTO selected_method_id
  FROM divination_methods
  WHERE code = 'hybrid-theme-insight-action';

  INSERT INTO reading_sessions (
    method_id,
    question
  )
  VALUES (
    selected_method_id,
    '下一步应该关注什么？'
  )
  RETURNING id INTO created_session_id;

  IF NOT EXISTS (
    SELECT 1
    FROM reading_sessions
    WHERE id = created_session_id
      AND method_version = 1
  ) THEN
    RAISE EXCEPTION 'reading method version initialization failed';
  END IF;

  SELECT position.id
  INTO selected_theme_position_id
  FROM divination_method_positions AS position
  WHERE position.method_id = selected_method_id
    AND position.position_code = 'theme';

  SELECT position.id
  INTO selected_insight_position_id
  FROM divination_method_positions AS position
  WHERE position.method_id = selected_method_id
    AND position.position_code = 'insight';

  INSERT INTO reading_draws (
    session_id,
    position_id,
    entity_id,
    orientation
  )
  VALUES (
    created_session_id,
    selected_theme_position_id,
    prompt_entity_id,
    'neutral'
  );

  INSERT INTO reading_draws (
    session_id,
    position_id,
    entity_id,
    orientation
  )
  VALUES (
    created_session_id,
    selected_insight_position_id,
    card_entity_id,
    'upright'
  );

  BEGIN
    INSERT INTO reading_draws (
      session_id,
      position_id,
      entity_id,
      orientation
    )
    VALUES (
      created_session_id,
      selected_insight_position_id,
      prompt_entity_id,
      'upright'
    );

    RAISE EXCEPTION 'prompt item was accepted in a tarot position';
  EXCEPTION
    WHEN check_violation THEN
      NULL;
  END;

  IF (
    SELECT count(*)
    FROM reading_draws
    WHERE session_id = created_session_id
  ) <> 2 THEN
    RAISE EXCEPTION 'hybrid reading smoke test failed';
  END IF;

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
