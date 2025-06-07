-- Add migration script here
CREATE TABLE ninja_access (
    id SERIAL PRIMARY KEY,
    firstname VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(98) NOT NULL,
    ninja_id INTEGER NOT NULL,
    CONSTRAINT fk_ninja_id FOREIGN KEY (ninja_id) REFERENCES ninja(id)
);

CREATE UNIQUE INDEX idx_ninja_access_ninja_id ON ninja_access(ninja_id);