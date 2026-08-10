WITH desired_recipe_counts(magic_name, card_name, required_count) AS (
    VALUES
        ('magma_spirit', 'Fire', 1),
        ('fire_lord_spirit', 'Fire', 2),
        ('bubble_spirit', 'Explode', 0)
),
ranked_magic_cards AS (
    SELECT
        mc.id,
        drc.required_count,
        ROW_NUMBER() OVER (
            PARTITION BY mc.magic_id, mc.card_id
            ORDER BY mc.id
        ) AS card_number
    FROM desired_recipe_counts drc
    JOIN magics m ON m.name = drc.magic_name
    JOIN cards c ON c.name = drc.card_name
    JOIN magic_cards mc
        ON mc.magic_id = m.id
       AND mc.card_id = c.id
)
DELETE FROM magic_cards mc
USING ranked_magic_cards rmc
WHERE mc.id = rmc.id
  AND rmc.card_number > rmc.required_count;

WITH desired_recipe_counts(magic_name, card_name, required_count) AS (
    VALUES
        ('magma_spirit', 'Fire', 1),
        ('fire_lord_spirit', 'Fire', 2),
        ('bubble_spirit', 'Explode', 0)
),
current_recipe_counts AS (
    SELECT
        drc.magic_name,
        drc.card_name,
        drc.required_count,
        COUNT(mc.id) AS current_count
    FROM desired_recipe_counts drc
    JOIN magics m ON m.name = drc.magic_name
    JOIN cards c ON c.name = drc.card_name
    LEFT JOIN magic_cards mc
        ON mc.magic_id = m.id
       AND mc.card_id = c.id
    GROUP BY drc.magic_name, drc.card_name, drc.required_count
),
missing_magic_cards AS (
    SELECT crc.magic_name, crc.card_name
    FROM current_recipe_counts crc
    CROSS JOIN LATERAL generate_series(
        1,
        GREATEST(crc.required_count - crc.current_count, 0)::INTEGER
    )
)
INSERT INTO magic_cards(magic_id, card_id)
SELECT m.id, c.id
FROM missing_magic_cards mmc
JOIN magics m ON m.name = mmc.magic_name
JOIN cards c ON c.name = mmc.card_name;
