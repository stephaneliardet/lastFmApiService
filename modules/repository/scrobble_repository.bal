// Repository pour la gestion des scrobbles (historique des écoutes) en base de données

import ballerina/sql;
import prive/lastfm_history.db;

# Repository pour les opérations CRUD sur les scrobbles
public isolated class ScrobbleRepository {

    private final db:DbClient dbClient;

    # Initialise le repository avec un client de base de données
    #
    # + dbClient - Client de base de données
    public isolated function init(db:DbClient dbClient) {
        self.dbClient = dbClient;
    }

    # Sauvegarde un scrobble
    #
    # + scrobble - Scrobble à sauvegarder
    # + return - Scrobble sauvegardé avec son ID, ou erreur
    public isolated function save(db:ScrobbleEntity scrobble) returns db:ScrobbleEntity|error {
        sql:ParameterizedQuery query = `
            INSERT INTO scrobbles (user_name, artist_name, track_name, album_name, listened_at, loved)
            VALUES (${scrobble.userName}, ${scrobble.artistName}, ${scrobble.trackName},
                    ${scrobble.albumName}, ${scrobble.listenedAt}, ${scrobble.loved ? 1 : 0})
        `;
        db:ExecutionResult result = check self.dbClient.execute(query);
        return {
            id: result.lastInsertId,
            userName: scrobble.userName,
            artistName: scrobble.artistName,
            trackName: scrobble.trackName,
            albumName: scrobble.albumName,
            listenedAt: scrobble.listenedAt,
            loved: scrobble.loved,
            createdAt: scrobble.createdAt
        };
    }

    # Sauvegarde plusieurs scrobbles en batch
    #
    # + scrobbles - Liste des scrobbles à sauvegarder
    # + return - Nombre de scrobbles insérés ou erreur
    public isolated function saveBatch(db:ScrobbleEntity[] scrobbles) returns int|error {
        if scrobbles.length() == 0 {
            return 0;
        }

        sql:ParameterizedQuery[] queries = [];
        foreach db:ScrobbleEntity scrobble in scrobbles {
            sql:ParameterizedQuery query = `
                INSERT INTO scrobbles (user_name, artist_name, track_name, album_name, listened_at, loved)
                VALUES (${scrobble.userName}, ${scrobble.artistName}, ${scrobble.trackName},
                        ${scrobble.albumName}, ${scrobble.listenedAt}, ${scrobble.loved ? 1 : 0})
            `;
            queries.push(query);
        }

        db:ExecutionResult[] results = check self.dbClient.batchExecute(queries);
        int totalInserted = 0;
        foreach db:ExecutionResult result in results {
            totalInserted += result.affectedRows;
        }
        return totalInserted;
    }

    # Recherche un scrobble par son ID
    #
    # + id - ID du scrobble
    # + return - Scrobble trouvé ou nil
    public isolated function findById(int id) returns db:ScrobbleEntity?|error {
        sql:ParameterizedQuery query = `
            SELECT id, user_name as userName, artist_name as artistName,
                   track_name as trackName, album_name as albumName,
                   listened_at as listenedAt, loved, created_at as createdAt
            FROM scrobbles
            WHERE id = ${id}
        `;
        record {}? result = check self.dbClient.queryOne(query);
        if result is record {} {
            return mapToScrobbleEntity(result);
        }
        return ();
    }

    # Récupère les scrobbles d'un utilisateur avec pagination
    #
    # + userName - Nom d'utilisateur
    # + options - Options de pagination
    # + return - Liste des scrobbles ou erreur
    public isolated function findByUser(string userName, db:PaginationOptions options = {}) returns db:ScrobbleEntity[]|error {
        sql:ParameterizedQuery query = `
            SELECT id, user_name as userName, artist_name as artistName,
                   track_name as trackName, album_name as albumName,
                   listened_at as listenedAt, loved, created_at as createdAt
            FROM scrobbles
            WHERE user_name = ${userName}
            ORDER BY listened_at DESC
            LIMIT ${options.'limit} OFFSET ${options.offset}
        `;
        return self.queryScrobbles(query);
    }

    # Récupère les scrobbles d'un utilisateur dans une plage de dates
    #
    # + userName - Nom d'utilisateur
    # + fromTimestamp - Timestamp de début (inclusif)
    # + toTimestamp - Timestamp de fin (inclusif)
    # + options - Options de pagination
    # + return - Liste des scrobbles ou erreur
    public isolated function findByUserAndDateRange(
            string userName,
            int fromTimestamp,
            int toTimestamp,
            db:PaginationOptions options = {}
    ) returns db:ScrobbleEntity[]|error {
        sql:ParameterizedQuery query = `
            SELECT id, user_name as userName, artist_name as artistName,
                   track_name as trackName, album_name as albumName,
                   listened_at as listenedAt, loved, created_at as createdAt
            FROM scrobbles
            WHERE user_name = ${userName}
              AND listened_at >= ${fromTimestamp}
              AND listened_at <= ${toTimestamp}
            ORDER BY listened_at DESC
            LIMIT ${options.'limit} OFFSET ${options.offset}
        `;
        return self.queryScrobbles(query);
    }

    # Récupère le dernier scrobble d'un utilisateur
    #
    # + userName - Nom d'utilisateur
    # + return - Dernier scrobble ou nil
    public isolated function findLastByUser(string userName) returns db:ScrobbleEntity?|error {
        sql:ParameterizedQuery query = `
            SELECT id, user_name as userName, artist_name as artistName,
                   track_name as trackName, album_name as albumName,
                   listened_at as listenedAt, loved, created_at as createdAt
            FROM scrobbles
            WHERE user_name = ${userName}
            ORDER BY listened_at DESC
            LIMIT 1
        `;
        record {}? result = check self.dbClient.queryOne(query);
        if result is record {} {
            return mapToScrobbleEntity(result);
        }
        return ();
    }

    # Vérifie si un scrobble existe déjà (pour éviter les doublons)
    #
    # + userName - Nom d'utilisateur
    # + artistName - Nom de l'artiste
    # + trackName - Nom du track
    # + listenedAt - Timestamp de l'écoute
    # + return - true si existe, false sinon
    public isolated function exists(string userName, string artistName, string trackName, int listenedAt) returns boolean|error {
        sql:ParameterizedQuery query = `
            SELECT 1 FROM scrobbles
            WHERE user_name = ${userName}
              AND artist_name = ${artistName}
              AND track_name = ${trackName}
              AND listened_at = ${listenedAt}
            LIMIT 1
        `;
        record {}? result = check self.dbClient.queryOne(query);
        return result is record {};
    }

    # Compte le nombre total de scrobbles d'un utilisateur
    #
    # + userName - Nom d'utilisateur
    # + return - Nombre de scrobbles ou erreur
    public isolated function countByUser(string userName) returns int|error {
        sql:ParameterizedQuery query = `
            SELECT COUNT(*) as count FROM scrobbles WHERE user_name = ${userName}
        `;
        record {}? result = check self.dbClient.queryOne(query);
        if result is record {} {
            return <int>result["count"];
        }
        return 0;
    }

    # Récupère les top artistes d'un utilisateur
    #
    # + userName - Nom d'utilisateur
    # + 'limit - Nombre maximum de résultats
    # + return - Liste des artistes avec leur nombre d'écoutes
    public isolated function getTopArtists(string userName, int 'limit = 10) returns record {|string artistName; int playCount;|}[]|error {
        sql:ParameterizedQuery query = `
            SELECT artist_name as artistName, COUNT(*) as playCount
            FROM scrobbles
            WHERE user_name = ${userName}
            GROUP BY artist_name
            ORDER BY playCount DESC
            LIMIT ${'limit}
        `;
        stream<record {}, sql:Error?> resultStream = check self.dbClient.query(query);
        record {|string artistName; int playCount;|}[] results = [];
        check from record {} row in resultStream
            do {
                results.push({
                    artistName: <string>row["artistName"],
                    playCount: <int>row["playCount"]
                });
            };
        return results;
    }

    # Récupère les top tracks d'un utilisateur
    #
    # + userName - Nom d'utilisateur
    # + 'limit - Nombre maximum de résultats
    # + return - Liste des tracks avec leur nombre d'écoutes
    public isolated function getTopTracks(string userName, int 'limit = 10) returns record {|string artistName; string trackName; int playCount;|}[]|error {
        sql:ParameterizedQuery query = `
            SELECT artist_name as artistName, track_name as trackName, COUNT(*) as playCount
            FROM scrobbles
            WHERE user_name = ${userName}
            GROUP BY artist_name, track_name
            ORDER BY playCount DESC
            LIMIT ${'limit}
        `;
        stream<record {}, sql:Error?> resultStream = check self.dbClient.query(query);
        record {|string artistName; string trackName; int playCount;|}[] results = [];
        check from record {} row in resultStream
            do {
                results.push({
                    artistName: <string>row["artistName"],
                    trackName: <string>row["trackName"],
                    playCount: <int>row["playCount"]
                });
            };
        return results;
    }

    # Supprime les scrobbles d'un utilisateur
    #
    # + userName - Nom d'utilisateur
    # + return - Nombre de lignes supprimées ou erreur
    public isolated function deleteByUser(string userName) returns int|error {
        sql:ParameterizedQuery query = `DELETE FROM scrobbles WHERE user_name = ${userName}`;
        db:ExecutionResult result = check self.dbClient.execute(query);
        return result.affectedRows;
    }

    # Exécute une requête et mappe les résultats en ScrobbleEntity
    #
    # + query - Requête SQL
    # + return - Liste des scrobbles ou erreur
    private isolated function queryScrobbles(sql:ParameterizedQuery query) returns db:ScrobbleEntity[]|error {
        stream<record {}, sql:Error?> resultStream = check self.dbClient.query(query);
        db:ScrobbleEntity[] scrobbles = [];
        check from record {} row in resultStream
            do {
                scrobbles.push(mapToScrobbleEntity(row));
            };
        return scrobbles;
    }
}

# Mappe un record de base de données vers ScrobbleEntity
#
# + row - Ligne de la base de données
# + return - ScrobbleEntity
isolated function mapToScrobbleEntity(record {} row) returns db:ScrobbleEntity {
    return {
        id: <int?>row["id"],
        userName: <string>row["userName"],
        artistName: <string>row["artistName"],
        trackName: <string>row["trackName"],
        albumName: <string?>row["albumName"],
        listenedAt: <int?>row["listenedAt"],
        loved: <int>row["loved"] == 1,
        createdAt: <string?>row["createdAt"]
    };
}
