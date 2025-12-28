// Repository pour la gestion des tracks en base de données

import ballerina/sql;
import prive/lastfm_history.db;

# Repository pour les opérations CRUD sur les tracks
public isolated class TrackRepository {

    private final db:DbClient dbClient;

    # Initialise le repository avec un client de base de données
    #
    # + dbClient - Client de base de données
    public isolated function init(db:DbClient dbClient) {
        self.dbClient = dbClient;
    }

    # Recherche un track par artiste et nom
    #
    # + artistName - Nom de l'artiste
    # + trackName - Nom du track
    # + return - Track trouvé ou nil
    public isolated function findByArtistAndTrack(string artistName, string trackName) returns db:TrackEntity?|error {
        sql:ParameterizedQuery query = `
            SELECT id, artist_name as artistName, track_name as trackName,
                   album_name as albumName, genres, composer,
                   quality_score as qualityScore,
                   created_at as createdAt, updated_at as updatedAt
            FROM tracks
            WHERE artist_name = ${artistName} AND track_name = ${trackName}
        `;
        record {}? result = check self.dbClient.queryOne(query);
        if result is record {} {
            return mapToTrackEntity(result);
        }
        return ();
    }

    # Recherche un track par son ID
    #
    # + id - ID du track
    # + return - Track trouvé ou nil
    public isolated function findById(int id) returns db:TrackEntity?|error {
        sql:ParameterizedQuery query = `
            SELECT id, artist_name as artistName, track_name as trackName,
                   album_name as albumName, genres, composer,
                   quality_score as qualityScore,
                   created_at as createdAt, updated_at as updatedAt
            FROM tracks
            WHERE id = ${id}
        `;
        record {}? result = check self.dbClient.queryOne(query);
        if result is record {} {
            return mapToTrackEntity(result);
        }
        return ();
    }

    # Sauvegarde un track (insert ou update)
    #
    # + track - Track à sauvegarder
    # + return - Track sauvegardé avec son ID, ou erreur
    public isolated function save(db:TrackEntity track) returns db:TrackEntity|error {
        // Vérifier si le track existe déjà
        db:TrackEntity? existing = check self.findByArtistAndTrack(track.artistName, track.trackName);

        if existing is db:TrackEntity {
            // Update
            sql:ParameterizedQuery query = `
                UPDATE tracks
                SET album_name = ${track.albumName},
                    genres = ${track.genres},
                    composer = ${track.composer},
                    quality_score = ${track.qualityScore},
                    updated_at = datetime('now')
                WHERE artist_name = ${track.artistName} AND track_name = ${track.trackName}
            `;
            _ = check self.dbClient.execute(query);
            return check self.findByArtistAndTrack(track.artistName, track.trackName) ?: track;
        } else {
            // Insert
            sql:ParameterizedQuery query = `
                INSERT INTO tracks (artist_name, track_name, album_name, genres, composer, quality_score)
                VALUES (${track.artistName}, ${track.trackName}, ${track.albumName},
                        ${track.genres}, ${track.composer}, ${track.qualityScore})
            `;
            db:ExecutionResult result = check self.dbClient.execute(query);
            return {
                id: result.lastInsertId,
                artistName: track.artistName,
                trackName: track.trackName,
                albumName: track.albumName,
                genres: track.genres,
                composer: track.composer,
                qualityScore: track.qualityScore,
                createdAt: track.createdAt,
                updatedAt: track.updatedAt
            };
        }
    }

    # Supprime un track par artiste et nom
    #
    # + artistName - Nom de l'artiste
    # + trackName - Nom du track
    # + return - Nombre de lignes supprimées ou erreur
    public isolated function deleteByArtistAndTrack(string artistName, string trackName) returns int|error {
        sql:ParameterizedQuery query = `
            DELETE FROM tracks WHERE artist_name = ${artistName} AND track_name = ${trackName}
        `;
        db:ExecutionResult result = check self.dbClient.execute(query);
        return result.affectedRows;
    }

    # Récupère tous les tracks d'un artiste
    #
    # + artistName - Nom de l'artiste
    # + options - Options de pagination
    # + return - Liste des tracks ou erreur
    public isolated function findByArtist(string artistName, db:PaginationOptions options = {}) returns db:TrackEntity[]|error {
        sql:ParameterizedQuery query = `
            SELECT id, artist_name as artistName, track_name as trackName,
                   album_name as albumName, genres, composer,
                   quality_score as qualityScore,
                   created_at as createdAt, updated_at as updatedAt
            FROM tracks
            WHERE artist_name = ${artistName}
            ORDER BY track_name ASC
            LIMIT ${options.'limit} OFFSET ${options.offset}
        `;
        return self.queryTracks(query);
    }

    # Récupère tous les tracks avec pagination
    #
    # + options - Options de pagination
    # + return - Liste des tracks ou erreur
    public isolated function findAll(db:PaginationOptions options = {}) returns db:TrackEntity[]|error {
        sql:ParameterizedQuery query = `
            SELECT id, artist_name as artistName, track_name as trackName,
                   album_name as albumName, genres, composer,
                   quality_score as qualityScore,
                   created_at as createdAt, updated_at as updatedAt
            FROM tracks
            ORDER BY artist_name ASC, track_name ASC
            LIMIT ${options.'limit} OFFSET ${options.offset}
        `;
        return self.queryTracks(query);
    }

    # Compte le nombre total de tracks
    #
    # + return - Nombre de tracks ou erreur
    public isolated function count() returns int|error {
        sql:ParameterizedQuery query = `SELECT COUNT(*) as count FROM tracks`;
        record {}? result = check self.dbClient.queryOne(query);
        if result is record {} {
            return <int>result["count"];
        }
        return 0;
    }

    # Compte le nombre de tracks d'un artiste
    #
    # + artistName - Nom de l'artiste
    # + return - Nombre de tracks ou erreur
    public isolated function countByArtist(string artistName) returns int|error {
        sql:ParameterizedQuery query = `
            SELECT COUNT(*) as count FROM tracks WHERE artist_name = ${artistName}
        `;
        record {}? result = check self.dbClient.queryOne(query);
        if result is record {} {
            return <int>result["count"];
        }
        return 0;
    }

    # Exécute une requête et mappe les résultats en TrackEntity
    #
    # + query - Requête SQL
    # + return - Liste des tracks ou erreur
    private isolated function queryTracks(sql:ParameterizedQuery query) returns db:TrackEntity[]|error {
        stream<record {}, sql:Error?> resultStream = check self.dbClient.query(query);
        db:TrackEntity[] tracks = [];
        check from record {} row in resultStream
            do {
                tracks.push(mapToTrackEntity(row));
            };
        return tracks;
    }
}

# Mappe un record de base de données vers TrackEntity
#
# + row - Ligne de la base de données
# + return - TrackEntity
isolated function mapToTrackEntity(record {} row) returns db:TrackEntity {
    return {
        id: <int?>row["id"],
        artistName: <string>row["artistName"],
        trackName: <string>row["trackName"],
        albumName: <string?>row["albumName"],
        genres: <string>row["genres"],
        composer: <string?>row["composer"],
        qualityScore: <decimal>row["qualityScore"],
        createdAt: <string?>row["createdAt"],
        updatedAt: <string?>row["updatedAt"]
    };
}
