WITH inserted_magic AS (
    INSERT INTO magics(name)
    SELECT 'shock_overload'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'shock_overload'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'shock_overload'
),
recipe_cards AS (
    SELECT *
    FROM (
        VALUES
            ('Explode', 1),
            ('Lightning', 2)
    ) AS recipe(card_name, required_count)
),
target_cards AS (
    SELECT c.id, rc.required_count
    FROM cards c
    JOIN recipe_cards rc ON rc.card_name = c.name
),
existing_magic_cards AS (
    SELECT mc.card_id, COUNT(*) AS existing_count
    FROM magic_cards mc
    JOIN target_magic tm ON tm.id = mc.magic_id
    GROUP BY mc.card_id
),
missing_magic_cards AS (
    SELECT tc.id
    FROM target_cards tc
    LEFT JOIN existing_magic_cards emc ON emc.card_id = tc.id
    CROSS JOIN generate_series(1, GREATEST(tc.required_count - COALESCE(emc.existing_count, 0), 0))
)
INSERT INTO magic_cards(magic_id, card_id)
SELECT tm.id, mmc.id
FROM target_magic tm
CROSS JOIN missing_magic_cards mmc;
