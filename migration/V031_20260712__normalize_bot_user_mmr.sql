UPDATE users bot_user
SET mmr = 1000
FROM bot_personas persona
WHERE bot_user.id = persona.user_id
  AND bot_user.mmr <> 1000;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM users bot_user
        JOIN bot_personas persona ON persona.user_id = bot_user.id
        WHERE bot_user.mmr <> 1000
    ) THEN
        RAISE EXCEPTION 'One or more bot users do not have MMR 1000';
    END IF;
END
$$;
