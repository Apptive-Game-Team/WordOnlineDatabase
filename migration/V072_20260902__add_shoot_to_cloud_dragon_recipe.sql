WITH cloud_dragon_shoot_card AS (
    SELECT m.id AS magic_id, c.id AS card_id
    FROM magics m
    CROSS JOIN cards c
    WHERE m.name = 'cloud_dragon'
      AND c.name = 'Shoot'
)
INSERT INTO magic_cards(magic_id, card_id)
SELECT cdsc.magic_id, cdsc.card_id
FROM cloud_dragon_shoot_card cdsc
WHERE NOT EXISTS (
    SELECT 1
    FROM magic_cards mc
    WHERE mc.magic_id = cdsc.magic_id
      AND mc.card_id = cdsc.card_id
);
