-- Add migration script here
CREATE TABLE ninja (
    id SERIAL PRIMARY KEY,
    age INTEGER NOT NULL,
    rank LEVEL NOT NULL DEFAULT 'GENIN'::LEVEL
);