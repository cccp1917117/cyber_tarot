BEGIN;

SET search_path TO tarot, public;

INSERT INTO divination_methods (
  code,
  name,
  description,
  version,
  status
)
VALUES
  (
    'prompt-single',
    '单提示物映照',
    '抽取一张视觉提示物，用自由联想回应当前问题。',
    1,
    'active'
  ),
  (
    'prompt-three-time',
    '提示物三时占卜',
    '分别抽取代表过去、现在和未来的三张提示物。',
    1,
    'active'
  ),
  (
    'tarot-single',
    '单张塔罗指引',
    '抽取一张塔罗牌，获取当前最重要的行动指引。',
    1,
    'active'
  ),
  (
    'tarot-three-time',
    '塔罗三时牌阵',
    '用三张塔罗牌观察过去影响、当前状态和未来趋势。',
    1,
    'active'
  ),
  (
    'hybrid-theme-insight-action',
    '主题・洞察・行动',
    '先以提示物确定主题，再用两张塔罗牌提供洞察与行动建议。',
    1,
    'active'
  )
ON CONFLICT (code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  version = EXCLUDED.version,
  status = EXCLUDED.status;

INSERT INTO divination_method_positions (
  method_id,
  position_code,
  position_order,
  name,
  instruction,
  draw_count,
  selection_strategy,
  orientation_mode
)
SELECT
  method.id,
  position.position_code,
  position.position_order,
  position.name,
  position.instruction,
  1,
  position.selection_strategy,
  position.orientation_mode
FROM (
  VALUES
    (
      'prompt-single',
      'focus',
      1,
      '当下映照',
      '观察图片中最先吸引你的部分，它正在映照什么？',
      'random',
      'none'
    ),
    (
      'prompt-three-time',
      'past',
      1,
      '过去',
      '什么旧经验仍在影响当前问题？',
      'random',
      'none'
    ),
    (
      'prompt-three-time',
      'present',
      2,
      '现在',
      '此刻最需要看见的状态是什么？',
      'random',
      'none'
    ),
    (
      'prompt-three-time',
      'future',
      3,
      '未来',
      '沿当前方向前进，什么可能逐渐显现？',
      'random',
      'none'
    ),
    (
      'tarot-single',
      'guidance',
      1,
      '今日指引',
      '这张牌建议你把注意力放在哪里？',
      'random',
      'upright_or_reversed'
    ),
    (
      'tarot-three-time',
      'past',
      1,
      '过去影响',
      '识别形成当前局面的关键影响。',
      'random',
      'upright_or_reversed'
    ),
    (
      'tarot-three-time',
      'present',
      2,
      '当前状态',
      '理解此刻正在运作的核心力量。',
      'random',
      'upright_or_reversed'
    ),
    (
      'tarot-three-time',
      'future',
      3,
      '未来趋势',
      '观察保持当前方向时最可能出现的趋势。',
      'random',
      'upright_or_reversed'
    ),
    (
      'hybrid-theme-insight-action',
      'theme',
      1,
      '主题',
      '由视觉提示物确定本次占卜真正需要关注的主题。',
      'weighted',
      'none'
    ),
    (
      'hybrid-theme-insight-action',
      'insight',
      2,
      '洞察',
      '揭示主题背后的结构、盲点或资源。',
      'random',
      'upright_or_reversed'
    ),
    (
      'hybrid-theme-insight-action',
      'action',
      3,
      '行动',
      '给出下一步可以实践的方向。',
      'random',
      'upright_or_reversed'
    )
) AS position(
  method_code,
  position_code,
  position_order,
  name,
  instruction,
  selection_strategy,
  orientation_mode
)
JOIN divination_methods AS method
  ON method.code = position.method_code
ON CONFLICT (method_id, position_code) DO UPDATE
SET
  position_order = EXCLUDED.position_order,
  name = EXCLUDED.name,
  instruction = EXCLUDED.instruction,
  draw_count = EXCLUDED.draw_count,
  selection_strategy = EXCLUDED.selection_strategy,
  orientation_mode = EXCLUDED.orientation_mode;

INSERT INTO divination_position_entity_kinds (
  position_id,
  entity_kind_code
)
SELECT
  position.id,
  allowed.entity_kind_code
FROM (
  VALUES
    ('prompt-single', 'focus', 'prompt_item'),
    ('prompt-three-time', 'past', 'prompt_item'),
    ('prompt-three-time', 'present', 'prompt_item'),
    ('prompt-three-time', 'future', 'prompt_item'),
    ('tarot-single', 'guidance', 'tarot_card'),
    ('tarot-three-time', 'past', 'tarot_card'),
    ('tarot-three-time', 'present', 'tarot_card'),
    ('tarot-three-time', 'future', 'tarot_card'),
    (
      'hybrid-theme-insight-action',
      'theme',
      'prompt_item'
    ),
    (
      'hybrid-theme-insight-action',
      'insight',
      'tarot_card'
    ),
    (
      'hybrid-theme-insight-action',
      'action',
      'tarot_card'
    )
) AS allowed(method_code, position_code, entity_kind_code)
JOIN divination_methods AS method
  ON method.code = allowed.method_code
JOIN divination_method_positions AS position
  ON position.method_id = method.id
  AND position.position_code = allowed.position_code
ON CONFLICT (position_id, entity_kind_code) DO NOTHING;

COMMIT;
