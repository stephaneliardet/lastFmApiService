// Scripts de migration pour créer et mettre à jour le schéma de la base de données

import ballerina/log;
import ballerina/sql;

# Version actuelle du schéma de la base de données
const int CURRENT_SCHEMA_VERSION = 2;

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
    if currentVersion < 2 {
        check migrateToV2(dbClient);
        check updateSchemaVersion(dbClient, 2);
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

# Migration vers la version 2 - Enrichissement amélioré
#
# + dbClient - Client de base de données
# + return - Erreur éventuelle
isolated function migrateToV2(DbClient dbClient) returns error? {
    log:printInfo("Applying migration v2: Enhanced enrichment schema");

    // === ARTISTS TABLE ===

    // Colonne name_normalized pour déduplication (accents, casse)
    sql:ParameterizedQuery addArtistNameNormalized = `
        ALTER TABLE artists ADD COLUMN name_normalized TEXT
    `;
    _ = check dbClient.execute(addArtistNameNormalized);

    // Colonne canonical_artist_id pour lier les variantes à l'artiste principal
    sql:ParameterizedQuery addCanonicalArtistId = `
        ALTER TABLE artists ADD COLUMN canonical_artist_id INTEGER REFERENCES artists(id)
    `;
    _ = check dbClient.execute(addCanonicalArtistId);

    // Colonne enrichment_source pour tracer l'origine du score
    // Valeurs: 'none', 'lastfm', 'musicbrainz', 'claude'
    sql:ParameterizedQuery addArtistEnrichmentSource = `
        ALTER TABLE artists ADD COLUMN enrichment_source TEXT DEFAULT 'none'
    `;
    _ = check dbClient.execute(addArtistEnrichmentSource);

    // Index sur name_normalized pour recherche rapide de doublons
    sql:ParameterizedQuery indexArtistNameNormalized = `
        CREATE INDEX IF NOT EXISTS idx_artists_name_normalized ON artists(name_normalized)
    `;
    _ = check dbClient.execute(indexArtistNameNormalized);

    // Index sur canonical_artist_id pour regroupement
    sql:ParameterizedQuery indexCanonicalArtist = `
        CREATE INDEX IF NOT EXISTS idx_artists_canonical ON artists(canonical_artist_id)
    `;
    _ = check dbClient.execute(indexCanonicalArtist);

    // === TRACKS TABLE ===

    // Colonnes pour l'enrichissement musique classique
    sql:ParameterizedQuery addTrackPeriod = `
        ALTER TABLE tracks ADD COLUMN period TEXT
    `;
    _ = check dbClient.execute(addTrackPeriod);

    sql:ParameterizedQuery addTrackMusicalForm = `
        ALTER TABLE tracks ADD COLUMN musical_form TEXT
    `;
    _ = check dbClient.execute(addTrackMusicalForm);

    sql:ParameterizedQuery addTrackOpusCatalog = `
        ALTER TABLE tracks ADD COLUMN opus_catalog TEXT
    `;
    _ = check dbClient.execute(addTrackOpusCatalog);

    sql:ParameterizedQuery addTrackWorkTitle = `
        ALTER TABLE tracks ADD COLUMN work_title TEXT
    `;
    _ = check dbClient.execute(addTrackWorkTitle);

    sql:ParameterizedQuery addTrackMovement = `
        ALTER TABLE tracks ADD COLUMN movement TEXT
    `;
    _ = check dbClient.execute(addTrackMovement);

    // Colonne enrichment_source pour tracer l'origine du score
    sql:ParameterizedQuery addTrackEnrichmentSource = `
        ALTER TABLE tracks ADD COLUMN enrichment_source TEXT DEFAULT 'none'
    `;
    _ = check dbClient.execute(addTrackEnrichmentSource);

    // === TABLE DE LIAISON TRACK_ARTISTS ===

    // Table pour gérer les artistes multiples par track (feat, collaboration, etc.)
    sql:ParameterizedQuery createTrackArtists = `
        CREATE TABLE IF NOT EXISTS track_artists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
            artist_id INTEGER NOT NULL REFERENCES artists(id) ON DELETE CASCADE,
            role TEXT DEFAULT 'main',
            position INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now')),
            UNIQUE(track_id, artist_id, role)
        )
    `;
    _ = check dbClient.execute(createTrackArtists);

    // Index pour recherche par track
    sql:ParameterizedQuery indexTrackArtistsTrack = `
        CREATE INDEX IF NOT EXISTS idx_track_artists_track ON track_artists(track_id)
    `;
    _ = check dbClient.execute(indexTrackArtistsTrack);

    // Index pour recherche par artiste
    sql:ParameterizedQuery indexTrackArtistsArtist = `
        CREATE INDEX IF NOT EXISTS idx_track_artists_artist ON track_artists(artist_id)
    `;
    _ = check dbClient.execute(indexTrackArtistsArtist);

    // Mettre à jour les enrichment_source existants basés sur enriched_by_ai
    sql:ParameterizedQuery updateExistingArtistSources = `
        UPDATE artists SET enrichment_source = CASE
            WHEN enriched_by_ai = 1 THEN 'claude'
            WHEN quality_score > 0 THEN 'musicbrainz'
            ELSE 'none'
        END
    `;
    _ = check dbClient.execute(updateExistingArtistSources);

    sql:ParameterizedQuery updateExistingTrackSources = `
        UPDATE tracks SET enrichment_source = CASE
            WHEN quality_score >= 0.8 THEN 'musicbrainz'
            WHEN quality_score > 0 THEN 'lastfm'
            ELSE 'none'
        END
    `;
    _ = check dbClient.execute(updateExistingTrackSources);

    log:printInfo("Migration v2 completed: Added name_normalized, canonical_artist_id, enrichment_source, classical metadata columns, and track_artists table");
}

# Vérifie si le schéma de la base de données est à jour
#
# + dbClient - Client de base de données
# + return - true si à jour, false sinon
public isolated function isSchemaUpToDate(DbClient dbClient) returns boolean|error {
    int currentVersion = check getCurrentSchemaVersion(dbClient);
    return currentVersion >= CURRENT_SCHEMA_VERSION;
}
