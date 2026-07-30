BEGIN;

SET search_path TO tarot, public;

DO $$
DECLARE
  constraint_name text;
BEGIN
  SELECT conname
  INTO constraint_name
  FROM pg_constraint
  WHERE conrelid = 'media_assets'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%storage_key%'
    AND pg_get_constraintdef(oid) ILIKE '%jpg%'
  LIMIT 1;

  IF constraint_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE media_assets DROP CONSTRAINT %I',
      constraint_name
    );
  END IF;

  SELECT conname
  INTO constraint_name
  FROM pg_constraint
  WHERE conrelid = 'media_assets'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%mime_type%'
    AND pg_get_constraintdef(oid) ILIKE '%image/jpeg%'
  LIMIT 1;

  IF constraint_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE media_assets DROP CONSTRAINT %I',
      constraint_name
    );
  END IF;
END;
$$;

ALTER TABLE media_assets
  ALTER COLUMN mime_type SET DEFAULT 'image/png';

ALTER TABLE media_assets
  ADD CONSTRAINT media_assets_png_extension_check
    CHECK (storage_key ~* '\.png$') NOT VALID,
  ADD CONSTRAINT media_assets_png_mime_type_check
    CHECK (mime_type = 'image/png') NOT VALID;

UPDATE entity_kinds
SET description = '以 PNG 图片为核心的视觉提示物'
WHERE code = 'prompt_item';

COMMENT ON TABLE media_assets IS
  'PNG 图片资源元数据；历史 JPG 记录需转换为 PNG 后才能再次更新。';

COMMIT;
