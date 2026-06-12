WITH target_magic AS (
    SELECT id
    FROM magics
    WHERE name = 'rain_cloud'
)
DELETE FROM magic_cards mc
USING target_magic tm
WHERE mc.magic_id = tm.id;

WITH target_magic AS (
    SELECT id
    FROM magics
    WHERE name = 'rain_cloud'
)
DELETE FROM user_magics um
USING target_magic tm
WHERE um.magic_id = tm.id;

WITH target_magic AS (
    SELECT id
    FROM magics
    WHERE name = 'rain_cloud'
)
DELETE FROM statistic_game_magics sgm
USING target_magic tm
WHERE sgm.magic_id = tm.id;

DELETE FROM magics
WHERE name = 'rain_cloud';

WITH target_game_object AS (
    SELECT id
    FROM game_objects
    WHERE name = 'rain_cloud'
)
DELETE FROM parameter_values pv
USING target_game_object tgo
WHERE pv.game_object_id = tgo.id;

DO $$
BEGIN
    IF to_regclass('public.game_object_tags') IS NOT NULL THEN
        DELETE FROM game_object_tags
        WHERE game_object_id IN (
            SELECT id
            FROM game_objects
            WHERE name = 'rain_cloud'
        );
    END IF;
END $$;

DELETE FROM game_objects
WHERE name = 'rain_cloud';
