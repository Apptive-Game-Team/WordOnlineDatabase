WITH target_magic AS (
    SELECT id
    FROM magics
    WHERE name = 'crater'
),
required_cards AS (
    SELECT id
    FROM cards
    WHERE name IN ('Build', 'Fire', 'Rock')
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

UPDATE parameter_values pv
SET value = updates.value
FROM game_objects go
JOIN (
    VALUES
        ('crater', 'attack_interval', 0.25),
        ('crater_ember', 'attack_range', 2.5)
) AS updates(game_object_name, parameter_name, value)
    ON updates.game_object_name = go.name
JOIN parameters p
    ON p.name = updates.parameter_name
WHERE pv.game_object_id = go.id
  AND pv.parameter_id = p.id;
