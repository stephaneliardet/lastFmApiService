import ballerina/http;
import ballerina/log;
import prive/lastfm_history.db;

# Configuration du port pour le service enrichi
configurable int enrichedServicePort = 8098;

# Service d'enrichissement partagé (initialisé au démarrage)
EnrichmentService? sharedEnricher = ();

# Initialise le service d'enrichissement partagé
#
# + return - Erreur éventuelle
function initSharedEnricher() returns error? {
    if sharedEnricher is () {
        sharedEnricher = check new ();
        log:printInfo("Shared enrichment service initialized");
    }
}

# Réponse de synchronisation
#
# + success - Indique si la synchronisation a réussi
# + message - Message descriptif
# + tracksProcessed - Nombre de tracks traités
# + artistsEnrichedByAI - Nombre d'artistes enrichis par Claude AI
# + cacheStats - Statistiques du cache
public type SyncResponse record {|
    boolean success;
    string message;
    int tracksProcessed;
    int artistsEnrichedByAI;
    record {|int artists; int tracks;|} cacheStats;
|};

# Réponse des scrobbles enrichis
#
# + user - Nom d'utilisateur
# + totalScrobbles - Nombre total de scrobbles en base
# + scrobbles - Liste des scrobbles enrichis
public type EnrichedScrobblesResponse record {|
    string user;
    int totalScrobbles;
    EnrichedScrobble[] scrobbles;
|};

# Scrobble enrichi avec métadonnées complètes
#
# + listenedAt - Timestamp Unix de l'écoute
# + datetime - Date et heure formatées
# + artist - Nom de l'artiste
# + track - Nom du morceau
# + album - Nom de l'album
# + loved - Indique si le track est aimé
# + genres - Liste des genres musicaux
# + composer - Nom du compositeur (si applicable)
# + isClassical - Indique si c'est de la musique classique
# + qualityScore - Score de qualité des métadonnées
public type EnrichedScrobble record {|
    int? listenedAt;
    string? datetime;
    string artist;
    string track;
    string? album;
    boolean loved;
    string[] genres;
    string? composer;
    boolean isClassical;
    decimal qualityScore;
|};

# Service REST pour les données enrichies
@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "POST", "OPTIONS"]
    }
}
service /api/enriched on new http:Listener(enrichedServicePort) {

    function init() returns error? {
        check initSharedEnricher();
        log:printInfo(string `Enriched data service started on port ${enrichedServicePort}`);
    }

    # Health check
    #
    # + return - Status du service
    resource function get health() returns json {
        return {status: "UP", 'service: "lastfm-enriched"};
    }

    # Synchronise les données d'un utilisateur avec Last.fm
    # Déclenche l'enrichissement MusicBrainz et Claude AI
    #
    # + username - Nom d'utilisateur Last.fm
    # + 'limit - Nombre de tracks à synchroniser (1-200, défaut: 50)
    # + aiLimit - Nombre maximum d'appels Claude AI (0-50, défaut: 50, 0 = désactivé)
    # + return - Résultat de la synchronisation
    resource function post users/[string username]/sync(
            int 'limit = 50,
            int aiLimit = 50
    ) returns SyncResponse|http:BadRequest|http:InternalServerError {

        // Validation
        if 'limit < 1 || 'limit > 200 {
            return <http:BadRequest>{body: {message: "limit must be between 1 and 200"}};
        }
        if aiLimit < 0 || aiLimit > 50 {
            return <http:BadRequest>{body: {message: "aiLimit must be between 0 and 50"}};
        }

        EnrichmentService? enricher = sharedEnricher;
        if enricher is () {
            return <http:InternalServerError>{body: {message: "Enrichment service not initialized"}};
        }

        do {
            // 1. Récupérer les écoutes récentes depuis Last.fm
            ScrobblesResponse recent = check lastfmClient.getRecentTracks(username, 'limit, 1);
            log:printInfo(string `Fetched ${recent.tracks.length()} tracks for user ${username}`);

            // 2. Enrichir avec MusicBrainz et sauvegarder dans SQLite
            EnrichedTrack[] enrichedTracks = check enricher.enrichTracks(recent.tracks, username);
            log:printInfo(string `Enriched ${enrichedTracks.length()} tracks`);

            // 3. Enrichir via Claude AI si nécessaire (et aiLimit > 0)
            int artistsEnrichedByAI = 0;
            if aiLimit > 0 {
                CachedArtist[] needsAI = enricher.getArtistsNeedingAIEnrichment();
                if needsAI.length() > 0 {
                    log:printInfo(string `${needsAI.length()} artists need AI enrichment (limit: ${aiLimit})`);
                    int|error aiResult = enricher.enrichLowScoreArtistsWithAI(aiLimit);
                    if aiResult is int && aiResult > 0 {
                        artistsEnrichedByAI = aiResult;
                        // Ré-enrichir avec les nouvelles données
                        _ = check enricher.enrichTracks(recent.tracks, username);
                    }
                }
            }

            // 4. Retourner le résultat
            var stats = enricher.getCacheStats();
            return {
                success: true,
                message: string `Synchronized ${enrichedTracks.length()} tracks for user ${username}`,
                tracksProcessed: enrichedTracks.length(),
                artistsEnrichedByAI: artistsEnrichedByAI,
                cacheStats: stats
            };

        } on fail error e {
            log:printError("Sync failed", 'error = e);
            return <http:InternalServerError>{body: {message: e.message()}};
        }
    }

    # Récupère les scrobbles enrichis d'un utilisateur depuis SQLite
    #
    # + username - Nom d'utilisateur Last.fm
    # + 'limit - Nombre de résultats (défaut: 50)
    # + offset - Décalage pour la pagination (défaut: 0)
    # + return - Liste des scrobbles enrichis
    resource function get users/[string username]/scrobbles(
            int 'limit = 50,
            int offset = 0
    ) returns EnrichedScrobblesResponse|http:BadRequest|http:InternalServerError {

        // Validation
        if 'limit < 1 || 'limit > 200 {
            return <http:BadRequest>{body: {message: "limit must be between 1 and 200"}};
        }
        if offset < 0 {
            return <http:BadRequest>{body: {message: "offset must be >= 0"}};
        }

        EnrichmentService? enricher = sharedEnricher;
        if enricher is () {
            return <http:InternalServerError>{body: {message: "Enrichment service not initialized"}};
        }

        do {
            CacheDb cache = enricher.getCache();

            // Récupérer les scrobbles depuis SQLite
            db:ScrobbleEntity[] scrobbles = check cache.getScrobbles(username, 'limit, offset);
            int totalCount = cache.countScrobbles(username);

            // Enrichir chaque scrobble avec les métadonnées de l'artiste et du track
            EnrichedScrobble[] enrichedScrobbles = [];
            foreach var scrobble in scrobbles {
                EnrichedScrobble enriched = check self.enrichScrobble(cache, scrobble);
                enrichedScrobbles.push(enriched);
            }

            return {
                user: username,
                totalScrobbles: totalCount,
                scrobbles: enrichedScrobbles
            };

        } on fail error e {
            log:printError("Failed to get scrobbles", 'error = e);
            return <http:InternalServerError>{body: {message: e.message()}};
        }
    }

    # Récupère les artistes enrichis depuis le cache
    #
    # + return - Liste des artistes enrichis
    resource function get artists() returns CachedArtist[]|http:InternalServerError {
        EnrichmentService? enricher = sharedEnricher;
        if enricher is () {
            return <http:InternalServerError>{body: {message: "Enrichment service not initialized"}};
        }

        return enricher.getAllCachedArtists();
    }

    # Récupère les tracks enrichis depuis le cache
    #
    # + return - Liste des tracks enrichis
    resource function get tracks() returns CachedTrack[]|http:InternalServerError {
        EnrichmentService? enricher = sharedEnricher;
        if enricher is () {
            return <http:InternalServerError>{body: {message: "Enrichment service not initialized"}};
        }

        return enricher.getAllCachedTracks();
    }

    # Enrichit un scrobble avec les métadonnées du cache
    #
    # + cache - Instance du cache
    # + scrobble - Scrobble à enrichir
    # + return - Scrobble enrichi
    private function enrichScrobble(CacheDb cache, db:ScrobbleEntity scrobble) returns EnrichedScrobble|error {
        // Récupérer les infos de l'artiste
        CachedArtist? artistInfo = cache.getArtist(scrobble.artistName);

        // Récupérer les infos du track
        CachedTrack? trackInfo = cache.getTrack(scrobble.artistName, scrobble.trackName);

        // Construire le scrobble enrichi
        string[] genres = [];
        string? composer = ();
        boolean isClassical = false;
        decimal qualityScore = 0.0d;

        if artistInfo is CachedArtist {
            genres = artistInfo.genres;
            // Déduire isClassical à partir des genres ou de isComposer
            isClassical = artistInfo.isComposer || self.hasClassicalGenre(artistInfo.genres);
            qualityScore = artistInfo.qualityScore;
        }

        if trackInfo is CachedTrack {
            composer = trackInfo.composer;
            if trackInfo.qualityScore > qualityScore {
                qualityScore = trackInfo.qualityScore;
            }
            // Fusionner les genres du track si différents
            foreach string g in trackInfo.genres {
                if genres.indexOf(g) is () {
                    genres.push(g);
                }
            }
        }

        // Formater la date
        string? datetime = ();
        if scrobble.listenedAt is int {
            datetime = formatTimestamp(<int>scrobble.listenedAt);
        }

        return {
            listenedAt: scrobble.listenedAt,
            datetime: datetime,
            artist: scrobble.artistName,
            track: scrobble.trackName,
            album: scrobble.albumName,
            loved: scrobble.loved,
            genres: genres,
            composer: composer,
            isClassical: isClassical,
            qualityScore: qualityScore
        };
    }

    # Vérifie si les genres contiennent de la musique classique
    #
    # + genres - Liste des genres
    # + return - true si musique classique
    private function hasClassicalGenre(string[] genres) returns boolean {
        string[] classicalKeywords = ["classical", "classique", "baroque", "romantic", "symphony", "opera", "chamber"];
        foreach string genre in genres {
            string lowerGenre = genre.toLowerAscii();
            foreach string keyword in classicalKeywords {
                if lowerGenre.includes(keyword) {
                    return true;
                }
            }
        }
        return false;
    }
}

# Formate un timestamp Unix en date lisible
#
# + timestamp - Timestamp Unix
# + return - Date formatée
function formatTimestamp(int timestamp) returns string {
    // Format simple YYYY-MM-DD HH:mm:ss
    int seconds = timestamp % 60;
    int minutes = (timestamp / 60) % 60;
    int hours = (timestamp / 3600) % 24;
    int days = timestamp / 86400;

    // Calcul approximatif de la date (depuis 1970-01-01)
    int year = 1970;
    int[] daysInMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

    while days >= 365 {
        boolean isLeap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
        int yearDays = isLeap ? 366 : 365;
        if days >= yearDays {
            days -= yearDays;
            year += 1;
        } else {
            break;
        }
    }

    boolean isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    if isLeapYear {
        daysInMonth[1] = 29;
    }

    int month = 1;
    foreach int i in 0 ..< 12 {
        if days >= daysInMonth[i] {
            days -= daysInMonth[i];
            month += 1;
        } else {
            break;
        }
    }

    int day = days + 1;

    return string `${year}-${month.toString().padStart(2, "0")}-${day.toString().padStart(2, "0")} ${hours.toString().padStart(2, "0")}:${minutes.toString().padStart(2, "0")}:${seconds.toString().padStart(2, "0")}`;
}
