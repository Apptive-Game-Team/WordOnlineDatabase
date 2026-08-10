WITH required_parameters(name) AS (
    VALUES
        ('attack_interval'),
        ('damage'),
        ('chain_lightning_cooldown')
)
INSERT INTO parameters(name)
SELECT rp.name
FROM required_parameters rp
WHERE NOT EXISTS (
    SELECT 1
    FROM parameters p
    WHERE p.name = rp.name
);

WITH cloud_dragon_values(parameter_name, value) AS (
    VALUES
        ('attack_interval', 1.0),
        ('damage', 5.0),
        ('chain_lightning_cooldown', 15.0)
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, cdv.value
FROM game_objects go
CROSS JOIN cloud_dragon_values cdv
JOIN parameters p
    ON p.name = cdv.parameter_name
WHERE go.name = 'cloud_dragon'
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;

WITH target_magic AS (
    SELECT id
    FROM magics
    WHERE name = 'cloud_dragon'
),
lightning_card AS (
    SELECT id
    FROM cards
    WHERE name = 'Lightning'
)
INSERT INTO magic_cards(magic_id, card_id)
SELECT tm.id, lc.id
FROM target_magic tm
CROSS JOIN lightning_card lc
WHERE NOT EXISTS (
    SELECT 1
    FROM magic_cards mc
    WHERE mc.magic_id = tm.id
      AND mc.card_id = lc.id
);
