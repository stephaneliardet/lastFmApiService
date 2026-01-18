// Types communs pour la couche de persistance

# Type de base de données supporté
#
# + SQLITE - Base de données SQLite (fichier local)
# + POSTGRESQL - Base de données PostgreSQL
# + MYSQL - Base de données MySQL
public enum DbType {
    SQLITE,
    POSTGRESQL,
    MYSQL
}

# Configuration de la base de données
#
# + dbType - Type de base de données
# + host - Hôte du serveur (pour PostgreSQL/MySQL)
# + port - Port du serveur (pour PostgreSQL/MySQL)
# + database - Nom de la base de données ou chemin du fichier SQLite
# + username - Nom d'utilisateur (pour PostgreSQL/MySQL)
# + password - Mot de passe (pour PostgreSQL/MySQL)
public type DbConfig record {|
    DbType dbType = SQLITE;
    string host = "localhost";
    int port = 5432;
    string database = "data/lastfm.db";
    string username = "";
    string password = "";
|};

# Résultat d'une opération d'écriture
#
# + affectedRows - Nombre de lignes affectées
# + lastInsertId - ID de la dernière ligne insérée (si applicable)
public type ExecutionResult record {|
    int affectedRows;
    int? lastInsertId;
|};

# Source d'enrichissement des données
public enum EnrichmentSource {
    NONE = "none",
    LASTFM = "lastfm",
    MUSICBRAINZ = "musicbrainz",
    CLAUDE = "claude"
}

# Entité Artiste pour la persistance
#
# + id - Identifiant unique
# + name - Nom de l'artiste
# + nameNormalized - Nom normalisé pour déduplication (sans accents, minuscules)
# + mbid - MusicBrainz ID (optionnel)
# + genres - Liste des genres musicaux (JSON)
# + composer - Nom du compositeur (si applicable)
# + isComposer - Indique si l'artiste est un compositeur
# + qualityScore - Score de qualité des données (0.0 à 1.0)
# + enrichedByAi - Indique si enrichi via Claude AI
# + enrichmentSource - Source ayant fourni le score actuel (none, lastfm, musicbrainz, claude)
# + canonicalArtistId - ID de l'artiste canonique si c'est une variante
# + createdAt - Date de création
# + updatedAt - Date de dernière mise à jour
public type ArtistEntity record {|
    int? id = ();
    string name;
    string? nameNormalized = ();
    string? mbid = ();
    string genres = "[]";
    string? composer = ();
    boolean isComposer = false;
    decimal qualityScore = 0.0d;
    boolean enrichedByAi = false;
    string enrichmentSource = "none";
    int? canonicalArtistId = ();
    string? createdAt = ();
    string? updatedAt = ();
|};

# Entité Track pour la persistance
#
# + id - Identifiant unique
# + artistName - Nom de l'artiste
# + trackName - Nom du morceau
# + albumName - Nom de l'album (optionnel)
# + genres - Liste des genres musicaux (JSON)
# + composer - Nom du compositeur (si applicable)
# + qualityScore - Score de qualité des données (0.0 à 1.0)
# + enrichmentSource - Source ayant fourni le score actuel (none, lastfm, musicbrainz, claude)
# + period - Période musicale (baroque, classical, romantic, modern, contemporary)
# + musicalForm - Forme musicale (symphony, concerto, sonata, etc.)
# + opusCatalog - Numéro de catalogue (BWV 1001, K. 466, Op. 12, etc.)
# + workTitle - Titre normalisé de l'oeuvre complète
# + movement - Mouvement si applicable (I. Allegro, etc.)
# + createdAt - Date de création
# + updatedAt - Date de dernière mise à jour
public type TrackEntity record {|
    int? id = ();
    string artistName;
    string trackName;
    string? albumName = ();
    string genres = "[]";
    string? composer = ();
    decimal qualityScore = 0.0d;
    string enrichmentSource = "none";
    string? period = ();
    string? musicalForm = ();
    string? opusCatalog = ();
    string? workTitle = ();
    string? movement = ();
    string? createdAt = ();
    string? updatedAt = ();
|};

# Entité Scrobble pour la persistance (historique des écoutes)
#
# + id - Identifiant unique
# + userName - Nom d'utilisateur Last.fm
# + artistName - Nom de l'artiste
# + trackName - Nom du morceau
# + albumName - Nom de l'album (optionnel)
# + listenedAt - Timestamp Unix de l'écoute
# + loved - Indique si le morceau est aimé
# + createdAt - Date de création de l'enregistrement
public type ScrobbleEntity record {|
    int? id = ();
    string userName;
    string artistName;
    string trackName;
    string? albumName = ();
    int? listenedAt = ();
    boolean loved = false;
    string? createdAt = ();
|};

# Rôles possibles d'un artiste sur un track
public enum ArtistRole {
    MAIN = "main",
    FEATURING = "featuring",
    ORCHESTRA = "orchestra",
    CONDUCTOR = "conductor",
    ENSEMBLE = "ensemble",
    SOLOIST = "soloist",
    ACCOMPANIST = "accompanist"
}

# Entité TrackArtist pour la table de liaison (multi-artistes par track)
#
# + id - Identifiant unique
# + trackId - ID du track
# + artistId - ID de l'artiste
# + role - Rôle de l'artiste (main, featuring, orchestra, etc.)
# + position - Position dans le crédit (0 = premier)
# + createdAt - Date de création
public type TrackArtistEntity record {|
    int? id = ();
    int trackId;
    int artistId;
    string role = "main";
    int position = 0;
    string? createdAt = ();
|};

# Options de pagination
#
# + 'limit - Nombre maximum de résultats
# + offset - Décalage pour la pagination
public type PaginationOptions record {|
    int 'limit = 50;
    int offset = 0;
|};

# Options de tri
#
# + sortField - Champ sur lequel trier
# + sortAscending - Ordre croissant si true, décroissant si false
public type SortOptions record {|
    string sortField = "id";
    boolean sortAscending = true;
|};