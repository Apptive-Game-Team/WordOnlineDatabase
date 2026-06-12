-- Add game_type column to statistic_games table
-- This migration adds support for PVP and Practice game types

ALTER TABLE statistic_games
ADD COLUMN game_type VARCHAR(20);

-- Optionally set default values for existing records
-- UPDATE statistic_games SET game_type = 'PVP' WHERE game_type IS NULL;

-- Create an index for better query performance when filtering by game type
CREATE INDEX idx_statistic_games_game_type ON statistic_games(game_type);
