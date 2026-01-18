import ballerina/file;
import ballerina/io;
import ballerina/log;
import ballerina/time;
import prive/lastfm_history.db;
import prive/lastfm_history.repository;
import prive/lastfm_history.utils;

# Configuration de la base de données cache
#
# + dbPath - Chemin vers le fichier JSON de cache
# + sqlitePath - Chemin vers la base de données SQLite
# + useSqlite - Activer la persistance SQLite (en plus de JSON)
public type CacheDbConfig record {|
    string dbPath = "data/cache.json";
    string sqlitePath = "data/lastfm.db";
    boolean useSqlite = true;
|};

# Artiste en cache
#
# + name - Nom de l'artiste
# + nameNormalized - Nom normalisé pour déduplication (sans accents, minuscules)
# + mbid - MusicBrainz ID (optionnel)
# + genres - Liste des genres musicaux
# + composer - Nom du compositeur (si applicable)
# + isComposer - Indique si l'artiste est un compositeur
# + qualityScore - Score de qualité des données (0.0 à 1.0)
# + enrichmentSource - Source ayant fourni le score (none, lastfm, musicbrainz, claude)
# + lastUpdated - Date de dernière mise à jour
# + enrichedByAI - Indique si enrichi via Claude AI
# + canonicalArtistId - ID de l'artiste canonique si c'est une variante
public type CachedArtist record {|
    string name;
    string? nameNormalized = ();
    string? mbid;
    string[] genres;
    string? composer;
    boolean isComposer;
    decimal qualityScore;
    string enrichmentSource = "none";
    string lastUpdated;
    boolean enrichedByAI;
    int? canonicalArtistId = ();
|};

# Track enrichi en cache
#
# + artistName - Nom de l'artiste
# + trackName - Nom du morceau
# + albumName - Nom de l'album (optionnel)
# + genres - Liste des genres musicaux
# + composer - Nom du compositeur (si applicable)
# + qualityScore - Score de qualité des données (0.0 à 1.0)
# + enrichmentSource - Source ayant fourni le score (none, lastfm, musicbrainz, claude)
# + period - Période musicale (baroque, classical, romantic, etc.)
# + musicalForm - Forme musicale (symphony, concerto, sonata, etc.)
# + opusCatalog - Numéro de catalogue (BWV 1001, K. 466, etc.)
# + workTitle - Titre normalisé de l'oeuvre complète
# + movement - Mouvement si applicable
# + lastUpdated - Date de dernière mise à jour
public type CachedTrack record {|
    string artistName;
    string trackName;
    string? albumName;
    string[] genres;
    string? composer;
    decimal qualityScore;
    string enrichmentSource = "none";
    string? period = ();
    string? musicalForm = ();
    string? opusCatalog = ();
    string? workTitle = ();
    string? movement = ();
    string lastUpdated;
|};

# Structure du cache complet
#
# + artists - Map des artistes indexés par nom
# + tracks - Map des tracks indexés par clé artiste|||track
type CacheData record {|
    map<CachedArtist> artists;
    map<CachedTrack> tracks;
|};

# Client pour la base de données cache (JSON + SQLite)
public class CacheDb {

    private final string dbPath;
    private CacheData cache = {artists: {}, tracks: {}};

    // SQLite
    private final boolean useSqlite;
    private db:DbClient? sqliteClient = ();
    private repository:ArtistRepository? artistRepo = ();
    private repository:TrackRepository? trackRepo = ();
    private repository:ScrobbleRepository? scrobbleRepo = ();

    public function init(CacheDbConfig config = {}) returns error? {
        self.dbPath = config.dbPath;
        self.useSqlite = config.useSqlite;

        check self.ensureDirectoryExists();
        self.cache = check self.loadCache();
        log:printInfo(string `Cache database initialized: ${self.dbPath}`);

        // Initialiser SQLite si activé
        if self.useSqlite {
            check self.initSqlite(config.sqlitePath);
        }
    }

    # Initialise la connexion SQLite et les repositories
    #
    # + sqlitePath - Chemin vers la base de données SQLite
    # + return - Erreur éventuelle
    private function initSqlite(string sqlitePath) returns error? {
        db:DbConfig sqliteConfig = {
            dbType: db:SQLITE,
            database: sqlitePath
        };

        db:DbClient dbClient = check db:createDbClient(sqliteConfig);
        self.sqliteClient = dbClient;
        self.artistRepo = new (dbClient);
        self.trackRepo = new (dbClient);
        self.scrobbleRepo = new (dbClient);

        log:printInfo(string `SQLite persistence enabled: ${sqlitePath}`);

        // Synchroniser les données JSON vers SQLite si la DB est vide
        check self.syncJsonToSqlite();
    }

    # Synchronise les données du cache JSON vers SQLite
    #
    # + return - Erreur éventuelle
    private function syncJsonToSqlite() returns error? {
        check self.syncArtistsToSqlite();
        check self.syncTracksToSqlite();
    }

    # Synchronise les artistes JSON vers SQLite
    #
    # + return - Erreur éventuelle
    private function syncArtistsToSqlite() returns error? {
        repository:ArtistRepository? repo = self.artistRepo;
        if repo is () {
            return;
        }

        // Vérifier si SQLite est vide
        int sqliteCount = check repo.count();
        if sqliteCount > 0 {
            log:printInfo(string `SQLite already contains ${sqliteCount} artists, skipping artist sync`);
            return;
        }

        // Synchroniser depuis JSON
        int jsonCount = self.cache.artists.length();
        if jsonCount == 0 {
            log:printInfo("No JSON artist data to sync to SQLite");
            return;
        }

        log:printInfo(string `Syncing ${jsonCount} artists from JSON to SQLite...`);
        int synced = 0;

        foreach CachedArtist artist in self.cache.artists {
            error? saveResult = self.saveArtistToSqlite(artist);
            if saveResult is error {
                log:printWarn(string `Failed to sync artist ${artist.name}: ${saveResult.message()}`);
            } else {
                synced += 1;
            }
        }

        log:printInfo(string `Synced ${synced}/${jsonCount} artists to SQLite`);
    }

    # Synchronise les tracks JSON vers SQLite
    #
    # + return - Erreur éventuelle
    private function syncTracksToSqlite() returns error? {
        repository:TrackRepository? repo = self.trackRepo;
        if repo is () {
            return;
        }

        // Vérifier si SQLite contient des tracks
        int sqliteCount = check repo.count();
        if sqliteCount > 0 {
            log:printInfo(string `SQLite already contains ${sqliteCount} tracks, skipping track sync`);
            return;
        }

        // Synchroniser depuis JSON
        int jsonCount = self.cache.tracks.length();
        if jsonCount == 0 {
            log:printInfo("No JSON track data to sync to SQLite");
            return;
        }

        log:printInfo(string `Syncing ${jsonCount} tracks from JSON to SQLite...`);
        int synced = 0;

        foreach CachedTrack track in self.cache.tracks {
            error? saveResult = self.saveTrackToSqlite(track);
            if saveResult is error {
                log:printWarn(string `Failed to sync track ${track.artistName} - ${track.trackName}: ${saveResult.message()}`);
            } else {
                synced += 1;
            }
        }

        log:printInfo(string `Synced ${synced}/${jsonCount} tracks to SQLite`);
    }

    # Assure que le répertoire data existe
    #
    # + return - Erreur éventuelle
    private function ensureDirectoryExists() returns error? {
        string dir = "data";
        if !check file:test(dir, file:EXISTS) {
            check file:createDir(dir);
        }
    }

    # Charge le cache depuis le fichier
    #
    # + return - Données du cache ou erreur
    private function loadCache() returns CacheData|error {
        if check file:test(self.dbPath, file:EXISTS) {
            string content = check io:fileReadString(self.dbPath);
            if content.length() > 0 {
                return check content.fromJsonStringWithType();
            }
        }
        // Cache vide par défaut
        return {artists: {}, tracks: {}};
    }

    # Sauvegarde le cache dans le fichier JSON
    #
    # + return - Erreur éventuelle
    private function saveCache() returns error? {
        string jsonContent = self.cache.toJsonString();
        check io:fileWriteString(self.dbPath, jsonContent);
    }

    # Récupère un artiste du cache (SQLite prioritaire, puis JSON)
    #
    # + artistName - Nom de l'artiste
    # + return - Artiste en cache ou nil si non trouvé
    public function getArtist(string artistName) returns CachedArtist? {
        // Essayer SQLite d'abord
        if self.useSqlite {
            CachedArtist?|error sqliteResult = self.getArtistFromSqlite(artistName);
            if sqliteResult is CachedArtist {
                return sqliteResult;
            }
        }

        // Fallback sur JSON
        return self.cache.artists[artistName];
    }

    # Récupère un artiste depuis SQLite
    #
    # + artistName - Nom de l'artiste
    # + return - Artiste ou nil ou erreur
    private function getArtistFromSqlite(string artistName) returns CachedArtist?|error {
        repository:ArtistRepository? repo = self.artistRepo;
        if repo is () {
            return ();
        }

        db:ArtistEntity? entity = check repo.findByName(artistName);
        if entity is db:ArtistEntity {
            return self.entityToCachedArtist(entity);
        }
        return ();
    }

    # Sauvegarde un artiste dans le cache (JSON + SQLite)
    #
    # + artist - Artiste à sauvegarder
    # + return - Erreur éventuelle
    public function saveArtist(CachedArtist artist) returns error? {
        // Sauvegarder dans JSON
        self.cache.artists[artist.name] = artist;
        check self.saveCache();

        // Sauvegarder dans SQLite si activé
        if self.useSqlite {
            check self.saveArtistToSqlite(artist);
        }

        log:printDebug(string `Cached artist: ${artist.name} (score: ${artist.qualityScore})`);
    }

    # Sauvegarde un artiste dans SQLite
    #
    # + artist - Artiste à sauvegarder
    # + return - Erreur éventuelle
    private function saveArtistToSqlite(CachedArtist artist) returns error? {
        repository:ArtistRepository? repo = self.artistRepo;
        if repo is () {
            return;
        }

        db:ArtistEntity entity = self.cachedArtistToEntity(artist);
        _ = check repo.save(entity);
    }

    # Convertit un CachedArtist en ArtistEntity pour SQLite
    #
    # + artist - Artiste à convertir
    # + return - Entité pour la DB
    private function cachedArtistToEntity(CachedArtist artist) returns db:ArtistEntity {
        // Calculer le nom normalisé si non fourni
        string normalizedName = artist.nameNormalized ?: utils:normalizeString(artist.name);

        return {
            name: artist.name,
            nameNormalized: normalizedName,
            mbid: artist.mbid,
            genres: artist.genres.toJsonString(),
            composer: artist.composer,
            isComposer: artist.isComposer,
            qualityScore: artist.qualityScore,
            enrichedByAi: artist.enrichedByAI,
            enrichmentSource: artist.enrichmentSource,
            canonicalArtistId: artist.canonicalArtistId
        };
    }

    # Convertit un ArtistEntity SQLite en CachedArtist
    #
    # + entity - Entité de la DB
    # + return - Artiste pour le cache
    private function entityToCachedArtist(db:ArtistEntity entity) returns CachedArtist {
        // Parser les genres depuis JSON
        string[] genres = [];
        string[]|error parsedGenres = entity.genres.fromJsonStringWithType();
        if parsedGenres is string[] {
            genres = parsedGenres;
        }

        return {
            name: entity.name,
            nameNormalized: entity.nameNormalized,
            mbid: entity.mbid,
            genres: genres,
            composer: entity.composer,
            isComposer: entity.isComposer,
            qualityScore: entity.qualityScore,
            enrichmentSource: entity.enrichmentSource,
            lastUpdated: entity.updatedAt ?: entity.createdAt ?: self.getCurrentTimestamp(),
            enrichedByAI: entity.enrichedByAi,
            canonicalArtistId: entity.canonicalArtistId
        };
    }

    # Génère une clé unique pour un track
    #
    # + artistName - Nom de l'artiste
    # + trackName - Nom du morceau
    # + return - Clé unique au format "artiste|||track"
    private function trackKey(string artistName, string trackName) returns string {
        return string `${artistName}|||${trackName}`;
    }

    # Récupère un track du cache (SQLite prioritaire, puis JSON)
    #
    # + artistName - Nom de l'artiste
    # + trackName - Nom du track
    # + return - Track en cache ou nil si non trouvé
    public function getTrack(string artistName, string trackName) returns CachedTrack? {
        // Essayer SQLite d'abord
        if self.useSqlite {
            CachedTrack?|error sqliteResult = self.getTrackFromSqlite(artistName, trackName);
            if sqliteResult is CachedTrack {
                return sqliteResult;
            }
        }

        // Fallback sur JSON
        string key = self.trackKey(artistName, trackName);
        return self.cache.tracks[key];
    }

    # Récupère un track depuis SQLite
    #
    # + artistName - Nom de l'artiste
    # + trackName - Nom du track
    # + return - Track ou nil ou erreur
    private function getTrackFromSqlite(string artistName, string trackName) returns CachedTrack?|error {
        repository:TrackRepository? repo = self.trackRepo;
        if repo is () {
            return ();
        }

        db:TrackEntity? entity = check repo.findByArtistAndTrack(artistName, trackName);
        if entity is db:TrackEntity {
            return self.entityToCachedTrack(entity);
        }
        return ();
    }

    # Sauvegarde un track dans le cache (JSON + SQLite)
    #
    # + track - Track à sauvegarder
    # + return - Erreur éventuelle
    public function saveTrack(CachedTrack track) returns error? {
        // Sauvegarder dans JSON
        string key = self.trackKey(track.artistName, track.trackName);
        self.cache.tracks[key] = track;
        check self.saveCache();

        // Sauvegarder dans SQLite si activé
        if self.useSqlite {
            check self.saveTrackToSqlite(track);
        }

        log:printDebug(string `Cached track: ${track.artistName} - ${track.trackName} (score: ${track.qualityScore})`);
    }

    # Sauvegarde un track dans SQLite
    #
    # + track - Track à sauvegarder
    # + return - Erreur éventuelle
    private function saveTrackToSqlite(CachedTrack track) returns error? {
        repository:TrackRepository? repo = self.trackRepo;
        if repo is () {
            return;
        }

        db:TrackEntity entity = self.cachedTrackToEntity(track);
        _ = check repo.save(entity);
    }

    # Convertit un CachedTrack en TrackEntity pour SQLite
    #
    # + track - Track à convertir
    # + return - Entité pour la DB
    private function cachedTrackToEntity(CachedTrack track) returns db:TrackEntity {
        return {
            artistName: track.artistName,
            trackName: track.trackName,
            albumName: track.albumName,
            genres: track.genres.toJsonString(),
            composer: track.composer,
            qualityScore: track.qualityScore,
            enrichmentSource: track.enrichmentSource,
            period: track.period,
            musicalForm: track.musicalForm,
            opusCatalog: track.opusCatalog,
            workTitle: track.workTitle,
            movement: track.movement
        };
    }

    # Convertit un TrackEntity SQLite en CachedTrack
    #
    # + entity - Entité de la DB
    # + return - Track pour le cache
    private function entityToCachedTrack(db:TrackEntity entity) returns CachedTrack {
        // Parser les genres depuis JSON
        string[] genres = [];
        string[]|error parsedGenres = entity.genres.fromJsonStringWithType();
        if parsedGenres is string[] {
            genres = parsedGenres;
        }

        return {
            artistName: entity.artistName,
            trackName: entity.trackName,
            albumName: entity.albumName,
            genres: genres,
            composer: entity.composer,
            qualityScore: entity.qualityScore,
            enrichmentSource: entity.enrichmentSource,
            period: entity.period,
            musicalForm: entity.musicalForm,
            opusCatalog: entity.opusCatalog,
            workTitle: entity.workTitle,
            movement: entity.movement,
            lastUpdated: entity.updatedAt ?: entity.createdAt ?: self.getCurrentTimestamp()
        };
    }

    # Récupère les artistes avec un score de qualité inférieur au seuil
    # (exclut les artistes déjà enrichis via Claude AI)
    #
    # + threshold - Seuil de qualité (ex: 0.8)
    # + 'limit - Nombre maximum de résultats
    # + return - Liste des artistes à enrichir
    public function getArtistsNeedingEnrichment(decimal threshold, int 'limit = 50) returns CachedArtist[] {
        // Essayer SQLite d'abord
        if self.useSqlite {
            CachedArtist[]|error sqliteResult = self.getArtistsNeedingEnrichmentFromSqlite(threshold, 'limit);
            if sqliteResult is CachedArtist[] && sqliteResult.length() > 0 {
                return sqliteResult;
            }
        }

        // Fallback sur JSON
        return self.getArtistsNeedingEnrichmentFromJson(threshold, 'limit);
    }

    # Récupère les artistes nécessitant enrichissement depuis SQLite
    #
    # + threshold - Seuil de qualité
    # + 'limit - Nombre maximum
    # + return - Liste des artistes ou erreur
    private function getArtistsNeedingEnrichmentFromSqlite(decimal threshold, int 'limit) returns CachedArtist[]|error {
        repository:ArtistRepository? repo = self.artistRepo;
        if repo is () {
            return [];
        }

        db:ArtistEntity[] entities = check repo.findNeedingEnrichment(threshold, 'limit);
        CachedArtist[] result = [];
        foreach db:ArtistEntity entity in entities {
            result.push(self.entityToCachedArtist(entity));
        }
        return result;
    }

    # Récupère les artistes nécessitant enrichissement depuis JSON
    #
    # + threshold - Seuil de qualité
    # + 'limit - Nombre maximum
    # + return - Liste des artistes
    private function getArtistsNeedingEnrichmentFromJson(decimal threshold, int 'limit) returns CachedArtist[] {
        CachedArtist[] result = [];
        int count = 0;

        foreach CachedArtist artist in self.cache.artists {
            // Exclure les artistes déjà enrichis via Claude AI
            if artist.qualityScore < threshold && !artist.enrichedByAI && count < 'limit {
                result.push(artist);
                count += 1;
            }
        }

        // Trier par score croissant (tri simple par insertion)
        int n = result.length();
        foreach int i in 1 ..< n {
            CachedArtist key = result[i];
            int j = i - 1;
            while j >= 0 && result[j].qualityScore > key.qualityScore {
                result[j + 1] = result[j];
                j = j - 1;
            }
            result[j + 1] = key;
        }

        return result;
    }

    # Compte le nombre d'artistes en cache
    #
    # + return - Nombre d'artistes
    public function countArtists() returns int {
        // Priorité SQLite
        if self.useSqlite {
            repository:ArtistRepository? repo = self.artistRepo;
            if repo is repository:ArtistRepository {
                int|error count = repo.count();
                if count is int {
                    return count;
                }
            }
        }
        return self.cache.artists.length();
    }

    # Compte le nombre de tracks en cache
    #
    # + return - Nombre de tracks
    public function countTracks() returns int {
        // Priorité SQLite
        if self.useSqlite {
            repository:TrackRepository? repo = self.trackRepo;
            if repo is repository:TrackRepository {
                int|error count = repo.count();
                if count is int {
                    return count;
                }
            }
        }
        return self.cache.tracks.length();
    }

    # Retourne le timestamp actuel formaté
    #
    # + return - Timestamp au format "YYYY-MM-DD HH:MM:SS"
    public function getCurrentTimestamp() returns string {
        time:Utc now = time:utcNow();
        time:Civil civil = time:utcToCivil(now);
        int second = civil.second is decimal ? <int>civil.second : 0;
        return string `${civil.year}-${civil.month}-${civil.day} ${civil.hour}:${civil.minute}:${second}`;
    }

    # Crée un CachedArtist à partir d'un ArtistInfo MusicBrainz
    #
    # + info - Informations artiste provenant de MusicBrainz
    # + return - Artiste formaté pour le cache
    public function createCachedArtist(ArtistInfo info) returns CachedArtist {
        return {
            name: info.name,
            nameNormalized: utils:normalizeString(info.name),
            mbid: info.mbid,
            genres: info.genres,
            composer: (),
            isComposer: info.isComposer,
            qualityScore: info.qualityScore,
            enrichmentSource: "musicbrainz",
            lastUpdated: self.getCurrentTimestamp(),
            enrichedByAI: false,
            canonicalArtistId: ()
        };
    }

    // ==================== SCROBBLES (SQLite uniquement) ====================

    # Sauvegarde un scrobble dans SQLite
    #
    # + userName - Nom d'utilisateur Last.fm
    # + artistName - Nom de l'artiste
    # + trackName - Nom du morceau
    # + albumName - Nom de l'album (optionnel)
    # + listenedAt - Timestamp Unix de l'écoute
    # + loved - Indique si le morceau est aimé
    # + return - Erreur éventuelle
    public function saveScrobble(string userName, string artistName, string trackName,
            string? albumName, int? listenedAt, boolean loved = false) returns error? {
        repository:ScrobbleRepository? repo = self.scrobbleRepo;
        if repo is () {
            return error("SQLite not enabled");
        }

        db:ScrobbleEntity scrobble = {
            userName: userName,
            artistName: artistName,
            trackName: trackName,
            albumName: albumName,
            listenedAt: listenedAt,
            loved: loved
        };
        _ = check repo.save(scrobble);
    }

    # Sauvegarde plusieurs scrobbles en batch
    #
    # + scrobbles - Liste des scrobbles à sauvegarder
    # + return - Nombre de scrobbles insérés ou erreur
    public function saveScrobblesBatch(db:ScrobbleEntity[] scrobbles) returns int|error {
        repository:ScrobbleRepository? repo = self.scrobbleRepo;
        if repo is () {
            return error("SQLite not enabled");
        }
        return repo.saveBatch(scrobbles);
    }

    # Vérifie si un scrobble existe déjà
    #
    # + userName - Nom d'utilisateur
    # + artistName - Nom de l'artiste
    # + trackName - Nom du track
    # + listenedAt - Timestamp de l'écoute
    # + return - true si existe, false sinon
    public function scrobbleExists(string userName, string artistName, string trackName, int listenedAt) returns boolean {
        repository:ScrobbleRepository? repo = self.scrobbleRepo;
        if repo is () {
            return false;
        }
        boolean|error result = repo.exists(userName, artistName, trackName, listenedAt);
        return result is boolean && result;
    }

    # Récupère les scrobbles d'un utilisateur avec pagination
    #
    # + userName - Nom d'utilisateur
    # + 'limit - Nombre maximum de résultats
    # + offset - Décalage pour la pagination
    # + return - Liste des scrobbles ou erreur
    public function getScrobbles(string userName, int 'limit = 50, int offset = 0) returns db:ScrobbleEntity[]|error {
        repository:ScrobbleRepository? repo = self.scrobbleRepo;
        if repo is () {
            return error("SQLite not enabled");
        }
        return repo.findByUser(userName, {'limit: 'limit, offset: offset});
    }

    # Récupère le dernier scrobble d'un utilisateur
    #
    # + userName - Nom d'utilisateur
    # + return - Dernier scrobble ou nil
    public function getLastScrobble(string userName) returns db:ScrobbleEntity?|error {
        repository:ScrobbleRepository? repo = self.scrobbleRepo;
        if repo is () {
            return ();
        }
        return repo.findLastByUser(userName);
    }

    # Compte le nombre de scrobbles d'un utilisateur
    #
    # + userName - Nom d'utilisateur
    # + return - Nombre de scrobbles
    public function countScrobbles(string userName) returns int {
        repository:ScrobbleRepository? repo = self.scrobbleRepo;
        if repo is () {
            return 0;
        }
        int|error count = repo.countByUser(userName);
        return count is int ? count : 0;
    }

    # Récupère les top artistes d'un utilisateur depuis les scrobbles
    #
    # + userName - Nom d'utilisateur
    # + 'limit - Nombre maximum de résultats
    # + return - Liste des artistes avec leur nombre d'écoutes
    public function getTopArtistsFromScrobbles(string userName, int 'limit = 10) returns record {|string artistName; int playCount;|}[]|error {
        repository:ScrobbleRepository? repo = self.scrobbleRepo;
        if repo is () {
            return error("SQLite not enabled");
        }
        return repo.getTopArtists(userName, 'limit);
    }

    # Récupère les top tracks d'un utilisateur depuis les scrobbles
    #
    # + userName - Nom d'utilisateur
    # + 'limit - Nombre maximum de résultats
    # + return - Liste des tracks avec leur nombre d'écoutes
    public function getTopTracksFromScrobbles(string userName, int 'limit = 10) returns record {|string artistName; string trackName; int playCount;|}[]|error {
        repository:ScrobbleRepository? repo = self.scrobbleRepo;
        if repo is () {
            return error("SQLite not enabled");
        }
        return repo.getTopTracks(userName, 'limit);
    }

    // ==================== TRACKS (SQLite uniquement pour nouvelles données) ====================

    # Récupère tous les tracks d'un artiste depuis SQLite
    #
    # + artistName - Nom de l'artiste
    # + return - Liste des tracks ou erreur
    public function getTracksByArtist(string artistName) returns db:TrackEntity[]|error {
        repository:TrackRepository? repo = self.trackRepo;
        if repo is () {
            return error("SQLite not enabled");
        }
        return repo.findByArtist(artistName);
    }

    // ==================== ACCÈS GLOBAL AU CACHE ====================

    # Récupère tous les artistes du cache JSON
    #
    # + return - Liste de tous les artistes
    public function getAllArtists() returns CachedArtist[] {
        return self.cache.artists.toArray();
    }

    # Récupère tous les tracks du cache JSON
    #
    # + return - Liste de tous les tracks
    public function getAllTracks() returns CachedTrack[] {
        return self.cache.tracks.toArray();
    }

    # Ferme les connexions
    #
    # + return - Erreur éventuelle
    public function close() returns error? {
        if self.sqliteClient is db:DbClient {
            check (<db:DbClient>self.sqliteClient).close();
            log:printInfo("SQLite connection closed");
        }
    }
}
