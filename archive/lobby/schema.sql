-- Decoration
CREATE TABLE decorations (
    id BIGSERIAL PRIMARY KEY,
    deco_type VARCHAR(10) NOT NULL , -- Hat, Cape
    name VARCHAR(20) NOT NULL
);

CREATE TABLE user_decorations (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT,
    decoration_id BIGINT REFERENCES decorations(id)
);

ALTER TABLE user_decorations ADD COLUMN is_equipped BOOLEAN DEFAULT FALSE;


-- Quest & Reward
ALTER TABLE cards
    ADD COLUMN IF NOT EXISTS unlock_condition_type VARCHAR(31),
    ADD COLUMN IF NOT EXISTS unlock_required_value INT;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS total_wins INT NOT NULL DEFAULT 0;

UPDATE cards
SET unlock_condition_type = 'WIN_COUNT',
    unlock_required_value = 5
WHERE name = 'Wind';

UPDATE cards
SET unlock_condition_type = 'WIN_COUNT',
    unlock_required_value = 10
WHERE name = 'Drop';

DROP TABLE quests;

CREATE TABLE quests (
    id BIGSERIAL PRIMARY KEY,
    progress_checker VARCHAR(31), -- spring bean name (return int progress_value)
    require_value INT NOT NULL,
    reward_giver VARCHAR(31) -- spring bean name
);

DROP TABLE reward_params;

CREATE TABLE reward_params (
    id BIGSERIAL PRIMARY KEY,
    quest_id BIGINT REFERENCES quests(id) ON DELETE CASCADE,
    name VARCHAR(31) NOT NULL,
    value INT NOT NULL
);

ALTER TABLE reward_params ADD CONSTRAINT uq_reward_params_quest_id_name UNIQUE (quest_id, name);

CREATE TABLE user_quests (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    quest_id BIGINT REFERENCES quests(id) ON DELETE CASCADE,
    state VARCHAR(15) NOT NULL DEFAULT 'IN_PROGRESS' -- 'PENDING', 'IN_PROGRESS', 'COMPLETED'
);


-- Adventure
CREATE TABLE adventures (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(31) NOT NULL,
    access_type VARCHAR(10) NOT NULL DEFAULT 'FREE'
);

CREATE TABLE stages (
    id BIGSERIAL PRIMARY KEY,
    adventure_id BIGINT REFERENCES adventures(id) ON DELETE CASCADE
);

CREATE TABLE scenarios (
    id BIGSERIAL PRIMARY KEY,
    stage_id BIGINT REFERENCES stages(id) ON DELETE CASCADE
);

CREATE TABLE user_adventures (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    adventure_id BIGINT REFERENCES adventures(id) ON DELETE CASCADE,
    state VARCHAR(10) NOT NULL DEFAULT 'INACTIVE' -- 'INACTIVE', 'ACTIVE', 'FINISHED'
);

CREATE TABLE user_stages (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    stage_id BIGINT REFERENCES stages(id) ON DELETE CASCADE,
    state VARCHAR(10) NOT NULL DEFAULT 'INACTIVE' -- 'INACTIVE', 'ACTIVE', 'FINISHED'
);

CREATE TABLE user_scenarios (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    scenario_id BIGINT REFERENCES scenarios(id) ON DELETE CASCADE,
    state VARCHAR(10) NOT NULL DEFAULT 'INACTIVE' -- 'INACTIVE', 'ACTIVE', 'FINISHED'
);


-- parameter versioning
ALTER TABLE parameter_values
    ADD COLUMN updated_at TIMESTAMP DEFAULT NOW();

CREATE INDEX idx_parameter_values_updated_at ON parameter_values(updated_at);

CREATE OR REPLACE FUNCTION update_updated_at_column()
    RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_parameter_values_modtime
    BEFORE UPDATE ON parameter_values
    FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();


-- magic cards versioning
ALTER TABLE magic_cards
    ADD COLUMN updated_at TIMESTAMP DEFAULT NOW();

CREATE INDEX idx_magic_cards_updated_at ON magic_cards(updated_at);

CREATE TRIGGER update_magic_cards_modtime
    BEFORE UPDATE ON magic_cards
    FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE user_cards DROP CONSTRAINT user_cards_user_id_fkey;
ALTER TABLE decks DROP CONSTRAINT decks_user_id_fkey;
ALTER TABLE user_adventures DROP CONSTRAINT user_adventures_user_id_fkey;
ALTER TABLE user_stages DROP CONSTRAINT user_stages_user_id_fkey;


-- refactoring
DROP TABLE user_adventures;
DROP TABLE user_stages;
ALTER TABLE user_scenarios
    ADD CONSTRAINT uq_user_adventures_user_id_scenario_id UNIQUE (user_id, scenario_id);

ALTER TABLE cards ADD COLUMN access_type VARCHAR(10) NOT NULL DEFAULT 'DEFAULT';
ALTER TABLE magics ADD COLUMN access_type VARCHAR(10) NOT NULL DEFAULT 'DEFAULT';
ALTER TABLE quests ADD COLUMN access_type VARCHAR(10) NOT NULL DEFAULT 'DEFAULT';


-- Deploy Status
CREATE TABLE deploy_status (
    id BIGSERIAL PRIMARY KEY,
    deploy_type VARCHAR(10) NOT NULL UNIQUE, -- DEV, PROD
    status VARCHAR(15) NOT NULL DEFAULT 'Healthy' -- Healthy, Maintenance, Down, Deploying
);

INSERT INTO deploy_status (deploy_type, status) VALUES ('DEV', 'Healthy');
INSERT INTO deploy_status (deploy_type, status) VALUES ('PROD', 'Healthy');