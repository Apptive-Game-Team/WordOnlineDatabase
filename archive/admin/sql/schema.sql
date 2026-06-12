
CREATE TABLE tags (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(20)
);

CREATE TABLE game_object_tags (
    id BIGSERIAL PRIMARY KEY,
    game_object_id BIGINT REFERENCES game_objects(id),
    tag_id BIGINT REFERENCES tags(id)
);

ALTER TABLE game_object_tags ADD CONSTRAINT uq_game_object_id_tag_id UNIQUE (game_object_id, tag_id);

ALTER TABLE cards ADD COLUMN game_object_id BIGINT REFERENCES game_objects(id);

CREATE TABLE servers (
    id BIGSERIAL PRIMARY KEY,
    protocol VARCHAR(10) NOT NULL,
    domain VARCHAR(255) NOT NULL,
    port INT NOT NULL,
    type VARCHAR(10) NOT NULL,
    state VARCHAR(10) NOT NULL DEFAULT 'INACTIVE'
);

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

CREATE TABLE deploy_status (
    id BIGSERIAL PRIMARY KEY,
    deploy_type VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL
);