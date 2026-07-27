WITH inserted_magic AS (
    INSERT INTO magics(name)
    SELECT 'seed_nest'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'seed_nest'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'seed_nest'
),
target_cards AS (
    SELECT id
    FROM cards
    WHERE name IN ('Build', 'Spawn', 'Nature')
)
INSERT INTO magic_cards(magic_id, card_id)
SELECT tm.id, tc.id
FROM target_magic tm
CROSS JOIN target_cards tc
WHERE NOT EXISTS (
    SELECT 1
    FROM magic_cards mc
    WHERE mc.magic_id = tm.id
      AND mc.card_id = tc.id
);
