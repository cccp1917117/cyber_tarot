BEGIN;

SET search_path TO tarot, public;

INSERT INTO association_taxonomies (code, name, description)
VALUES
  ('zodiac', '星座', '西方占星术的十二星座'),
  ('mbti', 'MBTI', 'Myers-Briggs 十六种人格类型')
ON CONFLICT (code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description;

INSERT INTO association_terms (
  taxonomy_id,
  code,
  label,
  sort_order,
  metadata
)
SELECT
  taxonomy.id,
  value.code,
  value.label,
  value.sort_order,
  value.metadata
FROM association_taxonomies AS taxonomy
CROSS JOIN (
  VALUES
    ('aries', '白羊座', 1, '{"symbol":"♈","element":"fire"}'::jsonb),
    ('taurus', '金牛座', 2, '{"symbol":"♉","element":"earth"}'::jsonb),
    ('gemini', '双子座', 3, '{"symbol":"♊","element":"air"}'::jsonb),
    ('cancer', '巨蟹座', 4, '{"symbol":"♋","element":"water"}'::jsonb),
    ('leo', '狮子座', 5, '{"symbol":"♌","element":"fire"}'::jsonb),
    ('virgo', '处女座', 6, '{"symbol":"♍","element":"earth"}'::jsonb),
    ('libra', '天秤座', 7, '{"symbol":"♎","element":"air"}'::jsonb),
    ('scorpio', '天蝎座', 8, '{"symbol":"♏","element":"water"}'::jsonb),
    ('sagittarius', '射手座', 9, '{"symbol":"♐","element":"fire"}'::jsonb),
    ('capricorn', '摩羯座', 10, '{"symbol":"♑","element":"earth"}'::jsonb),
    ('aquarius', '水瓶座', 11, '{"symbol":"♒","element":"air"}'::jsonb),
    ('pisces', '双鱼座', 12, '{"symbol":"♓","element":"water"}'::jsonb)
) AS value(code, label, sort_order, metadata)
WHERE taxonomy.code = 'zodiac'
ON CONFLICT (taxonomy_id, code) DO UPDATE
SET
  label = EXCLUDED.label,
  sort_order = EXCLUDED.sort_order,
  metadata = EXCLUDED.metadata;

INSERT INTO association_terms (
  taxonomy_id,
  code,
  label,
  sort_order,
  metadata
)
SELECT
  taxonomy.id,
  value.code,
  value.label,
  value.sort_order,
  jsonb_build_object(
    'energy',
    substr(upper(value.code), 1, 1),
    'information',
    substr(upper(value.code), 2, 1),
    'decision',
    substr(upper(value.code), 3, 1),
    'lifestyle',
    substr(upper(value.code), 4, 1)
  )
FROM association_taxonomies AS taxonomy
CROSS JOIN (
  VALUES
    ('intj', 'INTJ', 1),
    ('intp', 'INTP', 2),
    ('entj', 'ENTJ', 3),
    ('entp', 'ENTP', 4),
    ('infj', 'INFJ', 5),
    ('infp', 'INFP', 6),
    ('enfj', 'ENFJ', 7),
    ('enfp', 'ENFP', 8),
    ('istj', 'ISTJ', 9),
    ('isfj', 'ISFJ', 10),
    ('estj', 'ESTJ', 11),
    ('esfj', 'ESFJ', 12),
    ('istp', 'ISTP', 13),
    ('isfp', 'ISFP', 14),
    ('estp', 'ESTP', 15),
    ('esfp', 'ESFP', 16)
) AS value(code, label, sort_order)
WHERE taxonomy.code = 'mbti'
ON CONFLICT (taxonomy_id, code) DO UPDATE
SET
  label = EXCLUDED.label,
  sort_order = EXCLUDED.sort_order,
  metadata = EXCLUDED.metadata;

COMMIT;
