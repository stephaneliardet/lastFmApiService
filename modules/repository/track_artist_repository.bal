// Repository pour la gestion de la liaison tracks-artistes en base de données

import ballerina/sql;
import prive/lastfm_history.db;

# Repository pour les opérations CRUD sur la table de liaison track_artists
public isolated class TrackArtistRepository {

    private final db:DbClient dbClient;

    # Initialise le repository avec un client de base de données
    #
    # + dbClient - Client de base de données
    public isolated function init(db:DbClient dbClient) {
        self.dbClient = dbClient;
    }

    # Ajoute un lien artiste-track
    #
    # + trackArtist - Lien à créer
    # + return - Lien créé avec son ID, ou erreur
    public isolated function save(db:TrackArtistEntity trackArtist) returns db:TrackArtistEntity|error {
        // Vérifier si le lien existe déjà
        db:TrackArtistEntity? existing = check self.findByTrackArtistRole(
            trackArtist.trackId, trackArtist.artistId, trackArtist.role
        );

        if existing is db:TrackArtistEntity {
            // Update position si nécessaire
            sql:ParameterizedQuery query = `
                UPDATE track_artists
                SET position = ${trackArtist.position}
                WHERE track_id = ${trackArtist.trackId}
                  AND artist_id = ${trackArtist.artistId}
                  AND role = ${trackArtist.role}
            `;
            _ = check self.dbClient.execute(query);
            return check self.findByTrackArtistRole(
                trackArtist.trackId, trackArtist.artistId, trackArtist.role
            ) ?: trackArtist;
        } else {
            // Insert
            sql:ParameterizedQuery query = `
                INSERT INTO track_artists (track_id, artist_id, role, position)
                VALUES (${trackArtist.trackId}, ${trackArtist.artistId},
                        ${trackArtist.role}, ${trackArtist.position})
            `;
            db:ExecutionResult result = check self.dbClient.execute(query);
            return {
                id: result.lastInsertId,
                trackId: trackArtist.trackId,
                artistId: trackArtist.artistId,
                role: trackArtist.role,
                position: trackArtist.position,
                createdAt: trackArtist.createdAt
            };
        }
    }

    # Recherche un lien par track, artiste et rôle
    #
    # + trackId - ID du track
    # + artistId - ID de l'artiste
    # + role - Rôle de l'artiste
    # + return - Lien trouvé ou nil
    public isolated function findByTrackArtistRole(int trackId, int artistId, string role)
            returns db:TrackArtistEntity?|error {
        sql:ParameterizedQuery query = `
            SELECT id, track_id as trackId, artist_id as artistId,
                   role, position, created_at as createdAt
            FROM track_artists
            WHERE track_id = ${trackId} AND artist_id = ${artistId} AND role = ${role}
        `;
        record {}? result = check self.dbClient.queryOne(query);
        if result is record {} {
            return mapToTrackArtistEntity(result);
        }
        return ();
    }

    # Récupère tous les artistes liés à un track
    #
    # + trackId - ID du track
    # + return - Liste des liens ou erreur
    public isolated function findByTrack(int trackId) returns db:TrackArtistEntity[]|error {
        sql:ParameterizedQuery query = `
            SELECT id, track_id as trackId, artist_id as artistId,
                   role, position, created_at as createdAt
            FROM track_artists
            WHERE track_id = ${trackId}
            ORDER BY position ASC
        `;
        return self.queryTrackArtists(query);
    }

    # Récupère tous les tracks liés à un artiste
    #
    # + artistId - ID de l'artiste
    # + return - Liste des liens ou erreur
    public isolated function findByArtist(int artistId) returns db:TrackArtistEntity[]|error {
        sql:ParameterizedQuery query = `
            SELECT id, track_id as trackId, artist_id as artistId,
                   role, position, created_at as createdAt
            FROM track_artists
            WHERE artist_id = ${artistId}
            ORDER BY created_at DESC
        `;
        return self.queryTrackArtists(query);
    }

    # Supprime tous les liens d'un track
    #
    # + trackId - ID du track
    # + return - Nombre de lignes supprimées ou erreur
    public isolated function deleteByTrack(int trackId) returns int|error {
        sql:ParameterizedQuery query = `DELETE FROM track_artists WHERE track_id = ${trackId}`;
        db:ExecutionResult result = check self.dbClient.execute(query);
        return result.affectedRows;
    }

    # Supprime un lien spécifique
    #
    # + trackId - ID du track
    # + artistId - ID de l'artiste
    # + role - Rôle de l'artiste
    # + return - Nombre de lignes supprimées ou erreur
    public isolated function delete(int trackId, int artistId, string role) returns int|error {
        sql:ParameterizedQuery query = `
            DELETE FROM track_artists
            WHERE track_id = ${trackId} AND artist_id = ${artistId} AND role = ${role}
        `;
        db:ExecutionResult result = check self.dbClient.execute(query);
        return result.affectedRows;
    }

    # Exécute une requête et mappe les résultats en TrackArtistEntity
    #
    # + query - Requête SQL
    # + return - Liste des liens ou erreur
    private isolated function queryTrackArtists(sql:ParameterizedQuery query)
            returns db:TrackArtistEntity[]|error {
        stream<record {}, sql:Error?> resultStream = check self.dbClient.query(query);
        db:TrackArtistEntity[] trackArtists = [];
        check from record {} row in resultStream
            do {
                trackArtists.push(mapToTrackArtistEntity(row));
            };
        return trackArtists;
    }
}

# Mappe un record de base de données vers TrackArtistEntity
#
# + row - Ligne de la base de données
# + return - TrackArtistEntity
isolated function mapToTrackArtistEntity(record {} row) returns db:TrackArtistEntity {
    return {
        id: <int?>row["id"],
        trackId: <int>row["trackId"],
        artistId: <int>row["artistId"],
        role: <string>row["role"],
        position: <int>row["position"],
        createdAt: <string?>row["createdAt"]
    };
}
