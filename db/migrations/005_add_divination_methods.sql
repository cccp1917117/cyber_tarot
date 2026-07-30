BEGIN;

SET search_path TO tarot, public;

CREATE TABLE divination_methods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE
    CHECK (code ~ '^[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?$'),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  description text,
  version smallint NOT NULL DEFAULT 1 CHECK (version > 0),
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'active', 'archived')),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX divination_methods_status_idx
  ON divination_methods (status, code);
CREATE INDEX divination_methods_metadata_gin_idx
  ON divination_methods USING gin (metadata);

CREATE TRIGGER divination_methods_set_updated_at
BEFORE UPDATE ON divination_methods
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE divination_method_positions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  method_id uuid NOT NULL
    REFERENCES divination_methods(id) ON DELETE CASCADE,
  position_code text NOT NULL
    CHECK (position_code ~ '^[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?$'),
  position_order smallint NOT NULL CHECK (position_order > 0),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  instruction text,
  draw_count smallint NOT NULL DEFAULT 1
    CHECK (draw_count BETWEEN 1 AND 10),
  selection_strategy text NOT NULL DEFAULT 'random'
    CHECK (selection_strategy IN ('random', 'weighted', 'manual')),
  orientation_mode text NOT NULL DEFAULT 'none'
    CHECK (
      orientation_mode IN (
        'none',
        'upright_only',
        'upright_or_reversed'
      )
    ),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT divination_positions_method_code_unique
    UNIQUE (method_id, position_code),
  CONSTRAINT divination_positions_method_order_unique
    UNIQUE (method_id, position_order)
);

CREATE INDEX divination_method_positions_method_idx
  ON divination_method_positions (method_id, position_order);
CREATE INDEX divination_method_positions_metadata_gin_idx
  ON divination_method_positions USING gin (metadata);

CREATE TRIGGER divination_method_positions_set_updated_at
BEFORE UPDATE ON divination_method_positions
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE divination_position_entity_kinds (
  position_id uuid NOT NULL
    REFERENCES divination_method_positions(id) ON DELETE CASCADE,
  entity_kind_code text NOT NULL
    REFERENCES entity_kinds(code) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (position_id, entity_kind_code)
);

CREATE INDEX divination_position_entity_kinds_kind_idx
  ON divination_position_entity_kinds (entity_kind_code, position_id);

CREATE TABLE reading_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  method_id uuid NOT NULL
    REFERENCES divination_methods(id) ON DELETE RESTRICT,
  method_version smallint NOT NULL CHECK (method_version > 0),
  status text NOT NULL DEFAULT 'in_progress'
    CHECK (
      status IN (
        'pending',
        'in_progress',
        'completed',
        'cancelled'
      )
    ),
  question text,
  subject_ref text,
  context jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(context) = 'object'),
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reading_sessions_completion_check
    CHECK (status <> 'completed' OR completed_at IS NOT NULL)
);

CREATE INDEX reading_sessions_method_created_idx
  ON reading_sessions (method_id, created_at DESC);
CREATE INDEX reading_sessions_status_created_idx
  ON reading_sessions (status, created_at DESC);
CREATE INDEX reading_sessions_context_gin_idx
  ON reading_sessions USING gin (context);

CREATE FUNCTION initialize_reading_session()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  current_version smallint;
  current_status text;
BEGIN
  SELECT version, status
  INTO current_version, current_status
  FROM divination_methods
  WHERE id = NEW.method_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'divination method % does not exist',
      NEW.method_id
      USING ERRCODE = '23503';
  END IF;

  IF current_status <> 'active' THEN
    RAISE EXCEPTION
      'divination method % is not active',
      NEW.method_id
      USING ERRCODE = '23514';
  END IF;

  IF NEW.method_version IS NULL THEN
    NEW.method_version = current_version;
  ELSIF NEW.method_version IS DISTINCT FROM current_version THEN
    RAISE EXCEPTION
      'method version % does not match current version %',
      NEW.method_version,
      current_version
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER reading_sessions_initialize
BEFORE INSERT ON reading_sessions
FOR EACH ROW EXECUTE FUNCTION initialize_reading_session();

CREATE TRIGGER reading_sessions_set_updated_at
BEFORE UPDATE ON reading_sessions
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE reading_draws (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL
    REFERENCES reading_sessions(id) ON DELETE CASCADE,
  position_id uuid NOT NULL
    REFERENCES divination_method_positions(id) ON DELETE RESTRICT,
  entity_id uuid NOT NULL
    REFERENCES catalog_entities(id) ON DELETE RESTRICT,
  draw_order smallint NOT NULL DEFAULT 1 CHECK (draw_order > 0),
  orientation text NOT NULL DEFAULT 'neutral'
    CHECK (orientation IN ('neutral', 'upright', 'reversed')),
  interpretation text,
  user_response text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reading_draws_position_order_unique
    UNIQUE (session_id, position_id, draw_order),
  CONSTRAINT reading_draws_entity_unique
    UNIQUE (session_id, entity_id)
);

CREATE INDEX reading_draws_session_idx
  ON reading_draws (session_id, position_id, draw_order);
CREATE INDEX reading_draws_entity_idx
  ON reading_draws (entity_id);
CREATE INDEX reading_draws_metadata_gin_idx
  ON reading_draws USING gin (metadata);

CREATE FUNCTION validate_reading_draw()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  session_method_id uuid;
  position_method_id uuid;
  maximum_draw_count smallint;
  allowed_orientation_mode text;
  actual_entity_kind text;
BEGIN
  SELECT method_id
  INTO session_method_id
  FROM reading_sessions
  WHERE id = NEW.session_id;

  SELECT method_id, draw_count, orientation_mode
  INTO
    position_method_id,
    maximum_draw_count,
    allowed_orientation_mode
  FROM divination_method_positions
  WHERE id = NEW.position_id;

  SELECT kind_code
  INTO actual_entity_kind
  FROM catalog_entities
  WHERE id = NEW.entity_id;

  IF session_method_id IS NULL
     OR position_method_id IS NULL
     OR actual_entity_kind IS NULL THEN
    RAISE EXCEPTION
      'reading draw references a missing session, position, or entity'
      USING ERRCODE = '23503';
  END IF;

  IF session_method_id IS DISTINCT FROM position_method_id THEN
    RAISE EXCEPTION
      'position does not belong to the reading method'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.draw_order > maximum_draw_count THEN
    RAISE EXCEPTION
      'draw_order % exceeds position draw_count %',
      NEW.draw_order,
      maximum_draw_count
      USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM divination_position_entity_kinds
    WHERE position_id = NEW.position_id
      AND entity_kind_code = actual_entity_kind
  ) THEN
    RAISE EXCEPTION
      'entity kind % is not allowed at this position',
      actual_entity_kind
      USING ERRCODE = '23514';
  END IF;

  IF (
    allowed_orientation_mode = 'none'
    AND NEW.orientation <> 'neutral'
  ) OR (
    allowed_orientation_mode = 'upright_only'
    AND NEW.orientation <> 'upright'
  ) OR (
    allowed_orientation_mode = 'upright_or_reversed'
    AND NEW.orientation NOT IN ('upright', 'reversed')
  ) THEN
    RAISE EXCEPTION
      'orientation % is not allowed for mode %',
      NEW.orientation,
      allowed_orientation_mode
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER reading_draws_validate
BEFORE INSERT OR UPDATE OF
  session_id,
  position_id,
  entity_id,
  draw_order,
  orientation
ON reading_draws
FOR EACH ROW EXECUTE FUNCTION validate_reading_draw();

CREATE TRIGGER reading_draws_set_updated_at
BEFORE UPDATE ON reading_draws
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE divination_methods IS
  '可版本化的占卜方法模板。';
COMMENT ON TABLE divination_method_positions IS
  '占卜方法中的有序位置、抽取方式和方向规则。';
COMMENT ON TABLE reading_sessions IS
  '一次实际占卜及其问题、方法版本和上下文。';
COMMENT ON TABLE reading_draws IS
  '一次占卜中每个位置实际抽到的提示物或塔罗牌。';

COMMIT;
