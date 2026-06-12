
INSERT INTO user_magics(user_id, magic_id)
(
    SELECT u.id, m.id
    FROM users u CROSS JOIN magics m
    WHERE m.access_type = 'DEFAULT'
      AND NOT EXISTS (
        SELECT 1
        FROM user_magics um
        WHERE um.user_id = u.id AND um.magic_id = m.id
    )
)