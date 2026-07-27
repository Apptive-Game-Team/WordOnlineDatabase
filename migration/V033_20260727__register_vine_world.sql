WITH inserted_magic AS (
    INSERT INTO magics(name)
    SELECT 'vine_world'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'vine_world'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'vine_world'
),
required_cards(card_name, required_count) AS (
    VALUES
        ('Explode', 2),
        ('Spawn', 1),
        ('Nature', 2)
),
current_card_counts AS (
    SELECT mc.card_id, COUNT(*) AS current_count
    FROM magic_cards mc
    JOIN target_magic tm ON tm.id = mc.magic_id
    GROUP BY mc.card_id
)
INSERT INTO magic_cards(magic_id, card_id)
SELECT tm.id, c.id
FROM target_magic tm
JOIN required_cards rc ON TRUE
JOIN cards c ON c.name = rc.card_name
LEFT JOIN current_card_counts ccc ON ccc.card_id = c.id
CROSS JOIN LATERAL generate_series(
        1,
        GREATEST(rc.required_count - COALESCE(ccc.current_count, 0), 0)::integer
    )
WHERE rc.required_count > COALESCE(ccc.current_count, 0);
