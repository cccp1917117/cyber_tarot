BEGIN;

SET search_path TO tarot, public;

ALTER TABLE tarot_decks
  ADD COLUMN back_image_asset_id uuid
    REFERENCES media_assets(id) ON DELETE RESTRICT,
  ADD COLUMN back_is_reversible boolean NOT NULL DEFAULT true;

ALTER TABLE tarot_decks
  ADD CONSTRAINT tarot_decks_back_image_required
  CHECK (back_image_asset_id IS NOT NULL)
  NOT VALID;

CREATE UNIQUE INDEX tarot_decks_back_image_asset_unique
  ON tarot_decks (back_image_asset_id);

COMMENT ON COLUMN tarot_decks.back_image_asset_id IS
  '该套牌独有的卡背 PNG；推荐 storage_key 为 tarot/{deck_slug}/card-back.png。';
COMMENT ON COLUMN tarot_decks.back_is_reversible IS
  '卡背旋转 180 度后是否保持对称；false 表示卡背可能暴露正逆位。';

COMMIT;
