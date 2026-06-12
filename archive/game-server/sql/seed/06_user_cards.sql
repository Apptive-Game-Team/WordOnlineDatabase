INSERT INTO user_cards(user_id, card_id, count)
SELECT id, 11, 3
FROM users u
WHERE NOT EXISTS (
    SELECT 1
    FROM user_cards uc
    WHERE uc.user_id = u.id AND uc.card_id = 11
);
