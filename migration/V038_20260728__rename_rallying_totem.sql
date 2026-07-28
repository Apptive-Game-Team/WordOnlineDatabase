UPDATE magics
SET name = 'rallying_totem'
WHERE name = 'rallying_torch'
  AND NOT EXISTS (
      SELECT 1
      FROM magics
      WHERE name = 'rallying_totem'
  );

UPDATE game_objects
SET name = 'rallying_totem'
WHERE name = 'rallying_torch'
  AND NOT EXISTS (
      SELECT 1
      FROM game_objects
      WHERE name = 'rallying_totem'
  );

DELETE FROM magic_cards mc
USING magics m, cards c
WHERE mc.magic_id = m.id
  AND mc.card_id = c.id
  AND m.name = 'rallying_totem'
  AND c.name = 'Drop';

WITH target_magic AS (
    SELECT id
    FROM magics
    WHERE name = 'rallying_totem'
),
required_cards AS (
    SELECT id
    FROM cards
    WHERE name IN ('Build', 'Fire')
)
INSERT INTO magic_cards(magic_id, card_id)
SELECT tm.id, rc.id
FROM target_magic tm
CROSS JOIN required_cards rc
WHERE NOT EXISTS (
    SELECT 1
    FROM magic_cards mc
    WHERE mc.magic_id = tm.id
      AND mc.card_id = rc.id
);

INSERT INTO parameters(name)
SELECT 'range'
WHERE NOT EXISTS (
    SELECT 1
    FROM parameters
    WHERE name = 'range'
);

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, 2.0
FROM game_objects go
CROSS JOIN parameters p
WHERE go.name = 'rallying_totem'
  AND p.name = 'range'
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;
