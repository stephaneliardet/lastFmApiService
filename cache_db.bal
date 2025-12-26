import ballerina/file;
import ballerina/io;
import ballerina/log;
import ballerina/time;

# Configuration de la base de données cache
public type CacheDbConfig record {|
    string dbPath = "data/cache.json";
|};

# Artiste en cache
public type CachedArtist record {|
    string name;
    string? mbid;
    string[] genres;
    string? composer;
    boolean isComposer;
    decimal qualityScore;
    string lastUpdated;
    boolean enrichedByAI;
|};

# Track enrichi en cache
public type CachedTrack record {|
    string artistName;
    string trackName;
    string? albumName;
    string[] genres;
    string? composer;
    decimal qualityScore;
    string lastUpdated;
|};

# Structure du cache complet
type CacheData record {|
    map<CachedArtist> artists;
    map<CachedTrack> tracks;
|};

# Client pour la base de données cache (fichier JSON)
public class CacheDb {

    private final string dbPath;
    private CacheData cache = {artists: {}, tracks: {}};

    public function init(CacheDbConfig config = {}) returns error? {
        self.dbPath = config.dbPath;
        check self.ensureDirectoryExists();
        self.cache = check self.loadCache();
        log:printInfo(string `Cache database initialized: ${self.dbPath}`);
    }

    # Assure que le répertoire data existe
    private function ensureDirectoryExists() returns error? {
        string dir = "data";
        if !check file:test(dir, file:EXISTS) {
            check file:createDir(dir);
        }
    }

    # Charge le cache depuis le fichier
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

    # Sauvegarde le cache dans le fichier
    private function saveCache() returns error? {
        string jsonContent = self.cache.toJsonString();
        check io:fileWriteString(self.dbPath, jsonContent);
    }

    # Récupère un artiste du cache
    #
    # + artistName - Nom de l'artiste
    # + return - Artiste en cache ou nil si non trouvé
    public function getArtist(string artistName) returns CachedArtist? {
        return self.cache.artists[artistName];
    }

    # Sauvegarde un artiste dans le cache
    #
    # + artist - Artiste à sauvegarder
    # + return - Erreur éventuelle
    public function saveArtist(CachedArtist artist) returns error? {
        self.cache.artists[artist.name] = artist;
        check self.saveCache();
        log:printDebug(string `Cached artist: ${artist.name} (score: ${artist.qualityScore})`);
    }

    # Génère une clé unique pour un track
    private function trackKey(string artistName, string trackName) returns string {
        return string `${artistName}|||${trackName}`;
    }

    # Récupère un track du cache
    #
    # + artistName - Nom de l'artiste
    # + trackName - Nom du track
    # + return - Track en cache ou nil si non trouvé
    public function getTrack(string artistName, string trackName) returns CachedTrack? {
        string key = self.trackKey(artistName, trackName);
        return self.cache.tracks[key];
    }

    # Sauvegarde un track dans le cache
    #
    # + track - Track à sauvegarder
    # + return - Erreur éventuelle
    public function saveTrack(CachedTrack track) returns error? {
        string key = self.trackKey(track.artistName, track.trackName);
        self.cache.tracks[key] = track;
        check self.saveCache();
        log:printDebug(string `Cached track: ${track.artistName} - ${track.trackName} (score: ${track.qualityScore})`);
    }

    # Récupère les artistes avec un score de qualité inférieur au seuil
    # (exclut les artistes déjà enrichis via Claude AI)
    #
    # + threshold - Seuil de qualité (ex: 0.8)
    # + 'limit - Nombre maximum de résultats
    # + return - Liste des artistes à enrichir
    public function getArtistsNeedingEnrichment(decimal threshold, int 'limit = 50) returns CachedArtist[] {
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
    public function countArtists() returns int {
        return self.cache.artists.length();
    }

    # Compte le nombre de tracks en cache
    public function countTracks() returns int {
        return self.cache.tracks.length();
    }

    # Retourne le timestamp actuel formaté
    public function getCurrentTimestamp() returns string {
        time:Utc now = time:utcNow();
        time:Civil civil = time:utcToCivil(now);
        int second = civil.second is decimal ? <int>civil.second : 0;
        return string `${civil.year}-${civil.month}-${civil.day} ${civil.hour}:${civil.minute}:${second}`;
    }

    # Crée un CachedArtist à partir d'un ArtistInfo MusicBrainz
    public function createCachedArtist(ArtistInfo info) returns CachedArtist {
        return {
            name: info.name,
            mbid: info.mbid,
            genres: info.genres,
            composer: (),
            isComposer: info.isComposer,
            qualityScore: info.qualityScore,
            lastUpdated: self.getCurrentTimestamp(),
            enrichedByAI: false
        };
    }
}
