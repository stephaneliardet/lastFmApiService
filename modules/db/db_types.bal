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

# Entité Artiste pour la persistance
#
# + id - Identifiant unique
# + name - Nom de l'artiste
# + mbid - MusicBrainz ID (optionnel)
# + genres - Liste des genres musicaux (JSON)
# + composer - Nom du compositeur (si applicable)
# + isComposer - Indique si l'artiste est un compositeur
# + qualityScore - Score de qualité des données (0.0 à 1.0)
# + enrichedByAi - Indique si enrichi via Claude AI
# + createdAt - Date de création
# + updatedAt - Date de dernière mise à jour
public type ArtistEntity record {|
    int? id = ();
    string name;
    string? mbid = ();
    string genres = "[]";
    string? composer = ();
    boolean isComposer = false;
    decimal qualityScore = 0.0d;
    boolean enrichedByAi = false;
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