// Script de migration des données du cache JSON vers SQLite

import ballerina/file;
import ballerina/io;
import ballerina/log;

# Structure du cache JSON (correspond à cache_db.bal)
#
# + artists - Map des artistes en cache
# + tracks - Map des tracks en cache
type JsonCacheData record {|
    map<JsonCachedArtist> artists;
    map<JsonCachedTrack> tracks;
|};

# Artiste dans le cache JSON
#
# + name - Nom de l'artiste
# + mbid - MusicBrainz ID
# + genres - Liste des genres musicaux
# + composer - Nom du compositeur
# + isComposer - Indique si l'artiste est un compositeur
# + qualityScore - Score de qualité des données
# + lastUpdated - Date de dernière mise à jour
# + enrichedByAI - Indique si enrichi via Claude AI
type JsonCachedArtist record {|
    string name;
    string? mbid;
    string[] genres;
    string? composer;
    boolean isComposer;
    decimal qualityScore;
    string lastUpdated;
    boolean enrichedByAI;
|};

# Track dans le cache JSON
#
# + artistName - Nom de l'artiste
# + trackName - Nom du morceau
# + albumName - Nom de l'album
# + genres - Liste des genres musicaux
# + composer - Nom du compositeur
# + qualityScore - Score de qualité des données
# + lastUpdated - Date de dernière mise à jour
type JsonCachedTrack record {|
    string artistName;
    string trackName;
    string? albumName;
    string[] genres;
    string? composer;
    decimal qualityScore;
    string lastUpdated;
|};

# Résultat de la migration
#
# + artistsMigrated - Nombre d'artistes migrés
# + tracksMigrated - Nombre de tracks migrés
# + errors - Liste des erreurs rencontrées
public type MigrationResult record {|
    int artistsMigrated;
    int tracksMigrated;
    string[] errors;
|};

# Migre les données du cache JSON vers la base de données SQLite
#
# + jsonPath - Chemin vers le fichier cache.json
# + dbClient - Client de base de données cible
# + return - Résultat de la migration ou erreur
public isolated function migrateFromJsonCache(string jsonPath, DbClient dbClient) returns MigrationResult|error {
    log:printInfo(string `Starting migration from ${jsonPath}`);

    MigrationResult result = {
        artistsMigrated: 0,
        tracksMigrated: 0,
        errors: []
    };

    // Vérifier si le fichier JSON existe
    if !check file:test(jsonPath, file:EXISTS) {
        log:printInfo("No JSON cache file found, nothing to migrate");
        return result;
    }

    // Lire le fichier JSON
    string jsonContent = check io:fileReadString(jsonPath);
    if jsonContent.length() == 0 {
        log:printInfo("JSON cache file is empty, nothing to migrate");
        return result;
    }

    // Parser le JSON
    JsonCacheData cacheData = check jsonContent.fromJsonStringWithType();

    // Migrer les artistes
    log:printInfo(string `Migrating ${cacheData.artists.length()} artists...`);
    foreach [string, JsonCachedArtist] [name, artist] in cacheData.artists.entries() {
        error? migrationError = migrateArtist(dbClient, artist);
        if migrationError is error {
            result.errors.push(string `Artist "${name}": ${migrationError.message()}`);
        } else {
            result.artistsMigrated += 1;
        }
    }

    // Migrer les tracks
    log:printInfo(string `Migrating ${cacheData.tracks.length()} tracks...`);
    foreach [string, JsonCachedTrack] [key, track] in cacheData.tracks.entries() {
        error? migrationError = migrateTrack(dbClient, track);
        if migrationError is error {
            result.errors.push(string `Track "${key}": ${migrationError.message()}`);
        } else {
            result.tracksMigrated += 1;
        }
    }

    log:printInfo(string `Migration completed: ${result.artistsMigrated} artists, ${result.tracksMigrated} tracks`);
    if result.errors.length() > 0 {
        log:printWarn(string `${result.errors.length()} errors occurred during migration`);
    }

    return result;
}

# Migre un artiste du cache JSON vers la base de données
#
# + dbClient - Client de base de données
# + artist - Artiste à migrer
# + return - Erreur éventuelle
isolated function migrateArtist(DbClient dbClient, JsonCachedArtist artist) returns error? {
    // Convertir les genres en JSON string
    string genresJson = artist.genres.toJsonString();

    ArtistEntity entity = {
        name: artist.name,
        mbid: artist.mbid,
        genres: genresJson,
        composer: artist.composer,
        isComposer: artist.isComposer,
        qualityScore: artist.qualityScore,
        enrichedByAi: artist.enrichedByAI
    };

    // Vérifier si l'artiste existe déjà
    record {}? existing = check dbClient.queryOne(`SELECT id FROM artists WHERE name = ${artist.name}`);
    if existing is record {} {
        // Update
        _ = check dbClient.execute(`
            UPDATE artists
            SET mbid = ${entity.mbid},
                genres = ${entity.genres},
                composer = ${entity.composer},
                is_composer = ${entity.isComposer ? 1 : 0},
                quality_score = ${entity.qualityScore},
                enriched_by_ai = ${entity.enrichedByAi ? 1 : 0},
                updated_at = datetime('now')
            WHERE name = ${entity.name}
        `);
    } else {
        // Insert
        _ = check dbClient.execute(`
            INSERT INTO artists (name, mbid, genres, composer, is_composer, quality_score, enriched_by_ai)
            VALUES (${entity.name}, ${entity.mbid}, ${entity.genres}, ${entity.composer},
                    ${entity.isComposer ? 1 : 0}, ${entity.qualityScore}, ${entity.enrichedByAi ? 1 : 0})
        `);
    }
}

# Migre un track du cache JSON vers la base de données
#
# + dbClient - Client de base de données
# + track - Track à migrer
# + return - Erreur éventuelle
isolated function migrateTrack(DbClient dbClient, JsonCachedTrack track) returns error? {
    // Convertir les genres en JSON string
    string genresJson = track.genres.toJsonString();

    TrackEntity entity = {
        artistName: track.artistName,
        trackName: track.trackName,
        albumName: track.albumName,
        genres: genresJson,
        composer: track.composer,
        qualityScore: track.qualityScore
    };

    // Vérifier si le track existe déjà
    record {}? existing = check dbClient.queryOne(`
        SELECT id FROM tracks WHERE artist_name = ${track.artistName} AND track_name = ${track.trackName}
    `);
    if existing is record {} {
        // Update
        _ = check dbClient.execute(`
            UPDATE tracks
            SET album_name = ${entity.albumName},
                genres = ${entity.genres},
                composer = ${entity.composer},
                quality_score = ${entity.qualityScore},
                updated_at = datetime('now')
            WHERE artist_name = ${entity.artistName} AND track_name = ${entity.trackName}
        `);
    } else {
        // Insert
        _ = check dbClient.execute(`
            INSERT INTO tracks (artist_name, track_name, album_name, genres, composer, quality_score)
            VALUES (${entity.artistName}, ${entity.trackName}, ${entity.albumName},
                    ${entity.genres}, ${entity.composer}, ${entity.qualityScore})
        `);
    }
}

# Sauvegarde le cache JSON avant migration (backup)
#
# + jsonPath - Chemin vers le fichier cache.json
# + return - Chemin du backup ou erreur
public isolated function backupJsonCache(string jsonPath) returns string|error {
    if !check file:test(jsonPath, file:EXISTS) {
        return error("JSON cache file does not exist");
    }

    string backupPath = string `${jsonPath}.backup`;
    check file:copy(jsonPath, backupPath, file:REPLACE_EXISTING);
    log:printInfo(string `JSON cache backed up to ${backupPath}`);
    return backupPath;
}
