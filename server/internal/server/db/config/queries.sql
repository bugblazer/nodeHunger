/*
Query to fetch a user by username
*/
-- name: GetUserByUsername :one
SELECT * FROM users
WHERE username = ? LIMIT 1; --LIMIT 1 ensures only one row is returned

/*
Query to create a new user
It's taking username and password and inserting into the row
Lastly it returns the complete row along with ID in the RETURNING *; part
*/
-- name: CreateUser :one
INSERT INTO users (
    username, password_hash
) VALUES (
    ?, ?
)
RETURNING *;

/*Query to create a player from the user*/
-- name: CreatePlayer :one
INSERT INTO players (
    user_id, name
) VALUES (
    ?, ?
)
RETURNING *;

/*Query to fetch player through the user_id*/
-- name: GetPlayerByUserId :one
SELECT * FROM players
WHERE user_id = ? LIMIT 1;

/*Query to update the player's best score. exec means void (not returning anything)*/
-- name: UpdatePlayerBestScore :exec
UPDATE players
SET best_score = ?
WHERE id = ?;

-- name: GetTopScores :many
SELECT name, best_score
FROM players
ORDER BY best_score DESC
LIMIT ?
OFFSET ?;