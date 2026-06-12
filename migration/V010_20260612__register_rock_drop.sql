WITH inserted_magic AS (
    INSERT INTO magics(name)
    SELECT 'rock_drop'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'rock_drop'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'rock_drop'
),
target_cards AS (
    SELECT id
    FROM cards
    WHERE name IN ('Rock', 'Drop')
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
