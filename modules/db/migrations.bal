// Scripts de migration pour créer et mettre à jour le schéma de la base de données

import ballerina/log;
import ballerina/sql;

# Version actuelle du schéma de la base de données
const int CURRENT_SCHEMA_VERSION = 1;

# Exécute les migrations nécessaires pour mettre à jour le schéma
#
# + dbClient - Client de base de données
# + return - Erreur éventuelle
public isolated function runMigrations(DbClient dbClient) returns error? {
    // Créer la table de suivi des migrations si elle n'existe pas
    check createMigrationsTable(dbClient);

    // Récupérer la version actuelle du schéma
    int currentVersion = check getCurrentSchemaVersion(dbClient);
    log:printInfo(string `Current schema version: ${currentVersion}`);

    // Appliquer les migrations manquantes
    if currentVersion < 1 {
        check migrateToV1(dbClient);
        check updateSchemaVersion(dbClient, 1);
    }

    log:printInfo(string `Database schema up to date (version ${CURRENT_SCHEMA_VERSION})`);
}

# Crée la table de suivi des migrations
#
# + dbClient - Client de base de données
# + return - Erreur éventuelle
isolated function createMigrationsTable(DbClient dbClient) returns error? {
    sql:ParameterizedQuery query = `
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at TEXT DEFAULT (datetime('now'))
        )
    `;
    _ = check dbClient.execute(query);
}

# Récupère la version actuelle du schéma
#
# + dbClient - Client de base de données
# + return - Version actuelle ou 0 si aucune migration
isolated function getCurrentSchemaVersion(DbClient dbClient) returns int|error {
    sql:ParameterizedQuery query = `
        SELECT COALESCE(MAX(version), 0) as version FROM schema_migrations
    `;
    record {}? result = check dbClient.queryOne(query);
    if result is record {} {
        return <int>result["version"];
    }
    return 0;
}

# Met à jour la version du schéma
#
# + dbClient - Client de base de données
# + version - Nouvelle version
# + return - Erreur éventuelle
isolated function updateSchemaVersion(DbClient dbClient, int version) returns error? {
    sql:ParameterizedQuery query = `
        INSERT INTO schema_migrations (version) VALUES (${version})
    `;
    _ = check dbClient.execute(query);
    log:printInfo(string `Applied migration to version ${version}`);
}

# Migration vers la version 1 - Schéma initial
#
# + dbClient - Client de base de données
# + return - Erreur éventuelle
isolated function migrateToV1(DbClient dbClient) returns error? {
    log:printInfo("Applying migration v1: Initial schema");

    // Table des artistes
    sql:ParameterizedQuery createArtists = `
        CREATE TABLE IF NOT EXISTS artists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            mbid TEXT,
            genres TEXT DEFAULT '[]',
            composer TEXT,
            is_composer INTEGER DEFAULT 0,
            quality_score REAL DEFAULT 0.0,
            enriched_by_ai INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now'))
        )
    `;
    _ = check dbClient.execute(createArtists);

    // Index sur le nom d'artiste
    sql:ParameterizedQuery indexArtistName = `
        CREATE INDEX IF NOT EXISTS idx_artists_name ON artists(name)
    `;
    _ = check dbClient.execute(indexArtistName);

    // Index sur le score de qualité (pour trouver les artistes à enrichir)
    sql:ParameterizedQuery indexArtistScore = `
        CREATE INDEX IF NOT EXISTS idx_artists_quality ON artists(quality_score)
    `;
    _ = check dbClient.execute(indexArtistScore);

    // Table des tracks
    sql:ParameterizedQuery createTracks = `
        CREATE TABLE IF NOT EXISTS tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            artist_name TEXT NOT NULL,
            track_name TEXT NOT NULL,
            album_name TEXT,
            genres TEXT DEFAULT '[]',
            composer TEXT,
            quality_score REAL DEFAULT 0.0,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now')),
            UNIQUE(artist_name, track_name)
        )
    `;
    _ = check dbClient.execute(createTracks);

    // Index sur le nom d'artiste des tracks
    sql:ParameterizedQuery indexTrackArtist = `
        CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist_name)
    `;
    _ = check dbClient.execute(indexTrackArtist);

    // Table des scrobbles (historique des écoutes)
    sql:ParameterizedQuery createScrobbles = `
        CREATE TABLE IF NOT EXISTS scrobbles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_name TEXT NOT NULL,
            artist_name TEXT NOT NULL,
            track_name TEXT NOT NULL,
            album_name TEXT,
            listened_at INTEGER,
            loved INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now'))
        )
    `;
    _ = check dbClient.execute(createScrobbles);

    // Index sur l'utilisateur
    sql:ParameterizedQuery indexScrobbleUser = `
        CREATE INDEX IF NOT EXISTS idx_scrobbles_user ON scrobbles(user_name)
    `;
    _ = check dbClient.execute(indexScrobbleUser);

    // Index sur la date d'écoute
    sql:ParameterizedQuery indexScrobbleDate = `
        CREATE INDEX IF NOT EXISTS idx_scrobbles_listened ON scrobbles(listened_at)
    `;
    _ = check dbClient.execute(indexScrobbleDate);

    // Index composite utilisateur + date
    sql:ParameterizedQuery indexScrobbleUserDate = `
        CREATE INDEX IF NOT EXISTS idx_scrobbles_user_date ON scrobbles(user_name, listened_at)
    `;
    _ = check dbClient.execute(indexScrobbleUserDate);

    log:printInfo("Migration v1 completed: Created tables artists, tracks, scrobbles");
}

# Vérifie si le schéma de la base de données est à jour
#
# + dbClient - Client de base de données
# + return - true si à jour, false sinon
public isolated function isSchemaUpToDate(DbClient dbClient) returns boolean|error {
    int currentVersion = check getCurrentSchemaVersion(dbClient);
    return currentVersion >= CURRENT_SCHEMA_VERSION;
}
