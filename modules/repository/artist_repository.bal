// Repository pour la gestion des artistes en base de données

import ballerina/sql;
import prive/lastfm_history.db;

# Repository pour les opérations CRUD sur les artistes
public isolated class ArtistRepository {

    private final db:DbClient dbClient;

    # Initialise le repository avec un client de base de données
    #
    # + dbClient - Client de base de données
    public isolated function init(db:DbClient dbClient) {
        self.dbClient = dbClient;
    }

    # Recherche un artiste par son nom
    #
    # + name - Nom de l'artiste
    # + return - Artiste trouvé ou nil
    public isolated function findByName(string name) returns db:ArtistEntity?|error {
        sql:ParameterizedQuery query = `
            SELECT id, name, name_normalized as nameNormalized, mbid, genres, composer,
                   is_composer as isComposer, quality_score as qualityScore,
                   enriched_by_ai as enrichedByAi, enrichment_source as enrichmentSource,
                   canonical_artist_id as canonicalArtistId,
                   created_at as createdAt, updated_at as updatedAt
            FROM artists
            WHERE name = ${name}
        `;
        record {}? result = check self.dbClient.queryOne(query);
        if result is record {} {
            return mapToArtistEntity(result);
        }
        return ();
    }

    # Recherche un artiste par son ID
    #
    # + id - ID de l'artiste
    # + return - Artiste trouvé ou nil
    public isolated function findById(int id) returns db:ArtistEntity?|error {
        sql:ParameterizedQuery query = `
            SELECT id, name, name_normalized as nameNormalized, mbid, genres, composer,
                   is_composer as isComposer, quality_score as qualityScore,
                   enriched_by_ai as enrichedByAi, enrichment_source as enrichmentSource,
                   canonical_artist_id as canonicalArtistId,
                   created_at as createdAt, updated_at as updatedAt
            FROM artists
            WHERE id = ${id}
        `;
        record {}? result = check self.dbClient.queryOne(query);
        if result is record {} {
            return mapToArtistEntity(result);
        }
        return ();
    }

    # Sauvegarde un artiste (insert ou update)
    #
    # + artist - Artiste à sauvegarder
    # + return - Artiste sauvegardé avec son ID, ou erreur
    public isolated function save(db:ArtistEntity artist) returns db:ArtistEntity|error {
        // Vérifier si l'artiste existe déjà
        db:ArtistEntity? existing = check self.findByName(artist.name);

        if existing is db:ArtistEntity {
            // Update
            sql:ParameterizedQuery query = `
                UPDATE artists
                SET mbid = ${artist.mbid},
                    name_normalized = ${artist.nameNormalized},
                    genres = ${artist.genres},
                    composer = ${artist.composer},
                    is_composer = ${artist.isComposer ? 1 : 0},
                    quality_score = ${artist.qualityScore},
                    enriched_by_ai = ${artist.enrichedByAi ? 1 : 0},
                    enrichment_source = ${artist.enrichmentSource},
                    canonical_artist_id = ${artist.canonicalArtistId},
                    updated_at = datetime('now')
                WHERE name = ${artist.name}
            `;
            _ = check self.dbClient.execute(query);
            return check self.findByName(artist.name) ?: artist;
        } else {
            // Insert
            sql:ParameterizedQuery query = `
                INSERT INTO artists (name, name_normalized, mbid, genres, composer, is_composer,
                                     quality_score, enriched_by_ai, enrichment_source, canonical_artist_id)
                VALUES (${artist.name}, ${artist.nameNormalized}, ${artist.mbid}, ${artist.genres},
                        ${artist.composer}, ${artist.isComposer ? 1 : 0}, ${artist.qualityScore},
                        ${artist.enrichedByAi ? 1 : 0}, ${artist.enrichmentSource}, ${artist.canonicalArtistId})
            `;
            db:ExecutionResult result = check self.dbClient.execute(query);
            return {
                id: result.lastInsertId,
                name: artist.name,
                nameNormalized: artist.nameNormalized,
                mbid: artist.mbid,
                genres: artist.genres,
                composer: artist.composer,
                isComposer: artist.isComposer,
                qualityScore: artist.qualityScore,
                enrichedByAi: artist.enrichedByAi,
                enrichmentSource: artist.enrichmentSource,
                canonicalArtistId: artist.canonicalArtistId,
                createdAt: artist.createdAt,
                updatedAt: artist.updatedAt
            };
        }
    }

    # Supprime un artiste par son nom
    #
    # + name - Nom de l'artiste
    # + return - Nombre de lignes supprimées ou erreur
    public isolated function deleteByName(string name) returns int|error {
        sql:ParameterizedQuery query = `DELETE FROM artists WHERE name = ${name}`;
        db:ExecutionResult result = check self.dbClient.execute(query);
        return result.affectedRows;
    }

    # Récupère tous les artistes avec pagination
    #
    # + options - Options de pagination
    # + return - Liste des artistes ou erreur
    public isolated function findAll(db:PaginationOptions options = {}) returns db:ArtistEntity[]|error {
        sql:ParameterizedQuery query = `
            SELECT id, name, name_normalized as nameNormalized, mbid, genres, composer,
                   is_composer as isComposer, quality_score as qualityScore,
                   enriched_by_ai as enrichedByAi, enrichment_source as enrichmentSource,
                   canonical_artist_id as canonicalArtistId,
                   created_at as createdAt, updated_at as updatedAt
            FROM artists
            ORDER BY name ASC
            LIMIT ${options.'limit} OFFSET ${options.offset}
        `;
        return self.queryArtists(query);
    }

    # Récupère les artistes nécessitant un enrichissement
    #
    # + threshold - Seuil de qualité
    # + 'limit - Nombre maximum de résultats
    # + return - Liste des artistes ou erreur
    public isolated function findNeedingEnrichment(decimal threshold, int 'limit = 50) returns db:ArtistEntity[]|error {
        sql:ParameterizedQuery query = `
            SELECT id, name, name_normalized as nameNormalized, mbid, genres, composer,
                   is_composer as isComposer, quality_score as qualityScore,
                   enriched_by_ai as enrichedByAi, enrichment_source as enrichmentSource,
                   canonical_artist_id as canonicalArtistId,
                   created_at as createdAt, updated_at as updatedAt
            FROM artists
            WHERE quality_score < ${threshold} AND enriched_by_ai = 0
            ORDER BY quality_score ASC
            LIMIT ${'limit}
        `;
        return self.queryArtists(query);
    }

    # Compte le nombre total d'artistes
    #
    # + return - Nombre d'artistes ou erreur
    public isolated function count() returns int|error {
        sql:ParameterizedQuery query = `SELECT COUNT(*) as count FROM artists`;
        record {}? result = check self.dbClient.queryOne(query);
        if result is record {} {
            return <int>result["count"];
        }
        return 0;
    }

    # Recherche des artistes par genre
    #
    # + genre - Genre à rechercher
    # + options - Options de pagination
    # + return - Liste des artistes ou erreur
    public isolated function findByGenre(string genre, db:PaginationOptions options = {}) returns db:ArtistEntity[]|error {
        string pattern = string `%"${genre}"%`;
        sql:ParameterizedQuery query = `
            SELECT id, name, name_normalized as nameNormalized, mbid, genres, composer,
                   is_composer as isComposer, quality_score as qualityScore,
                   enriched_by_ai as enrichedByAi, enrichment_source as enrichmentSource,
                   canonical_artist_id as canonicalArtistId,
                   created_at as createdAt, updated_at as updatedAt
            FROM artists
            WHERE genres LIKE ${pattern}
            ORDER BY name ASC
            LIMIT ${options.'limit} OFFSET ${options.offset}
        `;
        return self.queryArtists(query);
    }

    # Recherche des artistes par nom normalisé (pour détection doublons)
    #
    # + normalizedName - Nom normalisé à rechercher
    # + return - Liste des artistes correspondants ou erreur
    public isolated function findByNormalizedName(string normalizedName) returns db:ArtistEntity[]|error {
        sql:ParameterizedQuery query = `
            SELECT id, name, name_normalized as nameNormalized, mbid, genres, composer,
                   is_composer as isComposer, quality_score as qualityScore,
                   enriched_by_ai as enrichedByAi, enrichment_source as enrichmentSource,
                   canonical_artist_id as canonicalArtistId,
                   created_at as createdAt, updated_at as updatedAt
            FROM artists
            WHERE name_normalized = ${normalizedName}
            ORDER BY quality_score DESC
        `;
        return self.queryArtists(query);
    }

    # Recherche l'artiste canonique pour un artiste donné
    #
    # + artistId - ID de l'artiste
    # + return - Artiste canonique ou l'artiste lui-même
    public isolated function findCanonical(int artistId) returns db:ArtistEntity?|error {
        db:ArtistEntity? artist = check self.findById(artistId);
        if artist is db:ArtistEntity {
            if artist.canonicalArtistId is int {
                return check self.findById(<int>artist.canonicalArtistId);
            }
            return artist;
        }
        return ();
    }

    # Exécute une requête et mappe les résultats en ArtistEntity
    #
    # + query - Requête SQL
    # + return - Liste des artistes ou erreur
    private isolated function queryArtists(sql:ParameterizedQuery query) returns db:ArtistEntity[]|error {
        stream<record {}, sql:Error?> resultStream = check self.dbClient.query(query);
        db:ArtistEntity[] artists = [];
        check from record {} row in resultStream
            do {
                artists.push(mapToArtistEntity(row));
            };
        return artists;
    }
}

# Mappe un record de base de données vers ArtistEntity
#
# + row - Ligne de la base de données
# + return - ArtistEntity
isolated function mapToArtistEntity(record {} row) returns db:ArtistEntity {
    return {
        id: <int?>row["id"],
        name: <string>row["name"],
        nameNormalized: <string?>row["nameNormalized"],
        mbid: <string?>row["mbid"],
        genres: <string>row["genres"],
        composer: <string?>row["composer"],
        isComposer: <int>row["isComposer"] == 1,
        qualityScore: <decimal>row["qualityScore"],
        enrichedByAi: <int>row["enrichedByAi"] == 1,
        enrichmentSource: <string?>row["enrichmentSource"] ?: "none",
        canonicalArtistId: <int?>row["canonicalArtistId"],
        createdAt: <string?>row["createdAt"],
        updatedAt: <string?>row["updatedAt"]
    };
}
