CREATE OR REPLACE FUNCTION allocate_bot_user_id()
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    candidate BIGINT;
BEGIN
    LOOP
        candidate := nextval('bot_user_id_seq');
        EXIT WHEN NOT EXISTS (SELECT 1 FROM users WHERE id = candidate);
    END LOOP;
    RETURN candidate;
END;
$$;
