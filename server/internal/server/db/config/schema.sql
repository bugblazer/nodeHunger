/*
Creating a table named users if it doesn't exist already
It creates 3 columns
id: an int which will be auto incrementing, it will be the primary key
username: string which must be unique, it can't be null
password_hash: string, can't be null
*/
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL
);

/*
Creating a table named players if it doesn't exist already
It will have 5 columns
id: auto incrementing primary key of type int
user_id: id to link the users table with players table, can't be null
name: player name of type string, can't be null
best_score: int type, can't be null and default is 0
color will store the color of the player blob
FOREIGN KEY (user_id) says that the user_id must be equal to the id in users table
*/
CREATE TABLE IF NOT EXISTS players (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    best_score INTEGER NOT NULL DEFAULT 0,
    color INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
);