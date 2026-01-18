import ballerina/io;
import ballerina/log;
import prive/lastfm_history.utils;

# Seuil de qualité pour déclencher l'enrichissement via Claude AI
const decimal QUALITY_THRESHOLD = 0.8d;

# Track enrichi avec métadonnées complètes
#
# + timestamp - Timestamp Unix de l'écoute
# + datetime - Date et heure formatées
# + artist - Nom de l'artiste
# + track - Nom du morceau
# + album - Nom de l'album
# + loved - Indique si le track est aimé par l'utilisateur
# + nowPlaying - Indique si le track est en cours de lecture
# + genres - Liste des genres musicaux
# + composer - Nom du compositeur (si applicable)
# + isClassical - Indique si c'est de la musique classique
# + qualityScore - Score de qualité des métadonnées (0.0 à 1.0)
public type EnrichedTrack record {|
    string timestamp?;
    string datetime?;
    string artist;
    string track;
    string album;
    boolean loved;
    boolean nowPlaying;
    string[] genres;
    string? composer;
    boolean isClassical;
    decimal qualityScore;
|};

# Nombre maximum d'appels Claude AI par exécution (défaut)
const int DEFAULT_MAX_CLAUDE_CALLS = 50;

# Service d'enrichissement des données musicales
public class EnrichmentService {

    private final MusicBrainzClient mbClient;
    private final CacheDb cache;
    private ClaudeClient? claudeClient = ();
    private int claudeCallsThisRun = 0;

    public function init() returns error? {
        self.mbClient = check new ();
        self.cache = check new ();

        // Initialiser le client Claude si la clé API est configurée
        ClaudeClient|error claudeInit = new ();
        if claudeInit is ClaudeClient {
            self.claudeClient = claudeInit;
            log:printInfo("Enrichment service initialized with Claude AI support");
        } else {
            log:printWarn("Claude AI client not initialized (API key missing?)");
            log:printInfo("Enrichment service initialized without Claude AI");
        }
    }

    # Enrichit une liste de tracks avec les métadonnées MusicBrainz
    # et les sauvegarde dans SQLite
    #
    # + tracks - Liste des tracks à enrichir
    # + userName - Nom d'utilisateur Last.fm (pour sauvegarder les scrobbles)
    # + return - Liste des tracks enrichis
    public function enrichTracks(SimpleTrack[] tracks, string userName = "") returns EnrichedTrack[]|error {
        EnrichedTrack[] enrichedTracks = [];

        foreach SimpleTrack track in tracks {
            EnrichedTrack enriched = check self.enrichTrack(track);
            enrichedTracks.push(enriched);

            // Sauvegarder le scrobble dans SQLite (si userName fourni et pas nowPlaying)
            if userName.length() > 0 && !track.nowPlaying {
                check self.saveScrobbleToSqlite(userName, track, enriched);
            }

            // Sauvegarder le track enrichi dans SQLite
            check self.saveTrackToSqlite(enriched);
        }

        return enrichedTracks;
    }

    # Sauvegarde un scrobble dans SQLite (évite les doublons)
    #
    # + userName - Nom d'utilisateur
    # + track - Track original
    # + enriched - Track enrichi
    # + return - Erreur éventuelle
    private function saveScrobbleToSqlite(string userName, SimpleTrack track, EnrichedTrack enriched) returns error? {
        // Convertir le timestamp string en int
        int? listenedAt = ();
        if track.timestamp is string {
            int|error ts = int:fromString(<string>track.timestamp);
            if ts is int {
                listenedAt = ts;
            }
        }

        // Vérifier si le scrobble existe déjà
        if listenedAt is int && self.cache.scrobbleExists(userName, track.artist, track.track, listenedAt) {
            return; // Déjà enregistré
        }

        // Sauvegarder le scrobble
        error? saveResult = self.cache.saveScrobble(
            userName,
            track.artist,
            track.track,
            track.album,
            listenedAt,
            track.loved
        );

        if saveResult is error {
            log:printDebug(string `Failed to save scrobble: ${saveResult.message()}`);
        }
    }

    # Sauvegarde un track enrichi dans SQLite
    #
    # + enriched - Track enrichi à sauvegarder
    # + return - Erreur éventuelle
    private function saveTrackToSqlite(EnrichedTrack enriched) returns error? {
        // Vérifier si le track existe déjà dans SQLite
        CachedTrack? existing = self.cache.getTrack(enriched.artist, enriched.track);
        if existing is CachedTrack && existing.qualityScore >= enriched.qualityScore {
            return; // Garder la version existante si meilleure qualité
        }

        // Valider le composer
        string? validatedComposer = ();
        if enriched.composer is string {
            if utils:isValidComposer(enriched.composer, enriched.album) {
                validatedComposer = enriched.composer;
            }
        }

        // Déterminer la source d'enrichissement
        string enrichmentSource = "lastfm"; // Source par défaut si on a des données
        if enriched.qualityScore >= 0.6d {
            enrichmentSource = "musicbrainz";
        }

        // Créer et sauvegarder le track
        CachedTrack cachedTrack = {
            artistName: enriched.artist,
            trackName: enriched.track,
            albumName: enriched.album,
            genres: enriched.genres,
            composer: validatedComposer,
            qualityScore: enriched.qualityScore,
            enrichmentSource: enrichmentSource,
            lastUpdated: self.cache.getCurrentTimestamp()
        };

        check self.cache.saveTrack(cachedTrack);
    }

    # Enrichit un track avec les métadonnées
    #
    # + track - Track à enrichir
    # + return - Track enrichi
    public function enrichTrack(SimpleTrack track) returns EnrichedTrack|error {
        // Récupérer les infos de l'artiste (cache ou MusicBrainz)
        CachedArtist? artistInfo = check self.getOrFetchArtist(track.artist);

        string[] genres = [];
        string? composer = ();
        boolean isClassical = false;
        decimal qualityScore = 0.0d;

        // 1. D'abord, essayer d'extraire le compositeur du titre
        // (fonctionne même sans données MusicBrainz)
        composer = self.extractComposerFromTitle(track.track);
        if composer is () {
            composer = self.extractComposerFromAlbum(track.album);
        }

        // 2. Détection de musique classique par le titre (backup)
        boolean classicalFromTitle = self.detectClassicalFromTitle(track.track, track.album);

        if artistInfo is CachedArtist {
            genres = artistInfo.genres;
            isClassical = self.isClassicalMusic(artistInfo) || classicalFromTitle;
            qualityScore = artistInfo.qualityScore;

            // Si l'artiste est un compositeur et pas de compositeur extrait, l'utiliser
            if artistInfo.isComposer && composer is () {
                composer = artistInfo.name;
            }

            // Bonus au score si on a trouvé un compositeur
            if composer is string {
                qualityScore = qualityScore + 0.2d;
                if qualityScore > 1.0d {
                    qualityScore = 1.0d;
                }
            }
        } else {
            // Pas d'info artiste, utiliser la détection par titre
            isClassical = classicalFromTitle;
            if composer is string {
                qualityScore = 0.3d; // Score minimum si on a au moins le compositeur
            }
        }

        return {
            timestamp: track.timestamp,
            datetime: track.datetime,
            artist: track.artist,
            track: track.track,
            album: track.album,
            loved: track.loved,
            nowPlaying: track.nowPlaying,
            genres: genres,
            composer: composer,
            isClassical: isClassical,
            qualityScore: qualityScore
        };
    }

    # Récupère un artiste du cache ou le fetch depuis MusicBrainz
    #
    # + artistName - Nom de l'artiste
    # + return - Artiste en cache ou nil
    private function getOrFetchArtist(string artistName) returns CachedArtist?|error {
        // 1. Vérifier le cache
        CachedArtist? cached = self.cache.getArtist(artistName);
        if cached is CachedArtist {
            // Si le score est >= 0.8, on garde les données enrichies (évite de rappeler Claude AI)
            if cached.qualityScore >= QUALITY_THRESHOLD {
                log:printDebug(string `Cache hit (score >= 0.8): ${artistName}`);
                return cached;
            }
            // Score < 0.8 : on va quand même vérifier MusicBrainz au cas où
            log:printDebug(string `Cache hit but low score (${cached.qualityScore}): ${artistName}`);
        }

        // 2. Rechercher sur MusicBrainz
        log:printDebug(string `Fetching from MusicBrainz: ${artistName}`);
        ArtistInfo|error mbInfo = self.mbClient.searchArtist(artistName);

        if mbInfo is error {
            log:printWarn(string `MusicBrainz lookup failed for: ${artistName} - ${mbInfo.message()}`);
            // Si on a déjà des données en cache, les garder
            if cached is CachedArtist {
                return cached;
            }
            // Sinon créer une entrée avec score bas
            CachedArtist fallback = {
                name: artistName,
                nameNormalized: utils:normalizeString(artistName),
                mbid: (),
                genres: [],
                composer: (),
                isComposer: false,
                qualityScore: 0.0d,
                enrichmentSource: "none",
                lastUpdated: self.cache.getCurrentTimestamp(),
                enrichedByAI: false,
                canonicalArtistId: ()
            };
            check self.cache.saveArtist(fallback);
            return fallback;
        }

        // 3. Comparer avec le cache existant
        CachedArtist newArtist = self.cache.createCachedArtist(mbInfo);

        // Si les données en cache ont un meilleur score, les garder
        if cached is CachedArtist && cached.qualityScore > newArtist.qualityScore {
            log:printDebug(string `Keeping cached data (better score): ${artistName}`);
            return cached;
        }

        // 4. Sauvegarder les nouvelles données
        check self.cache.saveArtist(newArtist);

        log:printInfo(string `Enriched artist: ${artistName} (genres: ${mbInfo.genres.toString()}, score: ${mbInfo.qualityScore})`);

        return newArtist;
    }

    # Détermine si c'est de la musique classique
    #
    # + artist - Artiste à analyser
    # + return - Vrai si musique classique détectée
    private function isClassicalMusic(CachedArtist artist) returns boolean {
        string[] classicalKeywords = ["classical", "baroque", "romantic", "opera", "symphony", "chamber"];

        foreach string genre in artist.genres {
            string lowerGenre = genre.toLowerAscii();
            foreach string keyword in classicalKeywords {
                if lowerGenre.includes(keyword) {
                    return true;
                }
            }
        }

        return artist.isComposer;
    }

    # Extrait le compositeur du titre du track ou de l'album.
    # Patterns reconnus:
    # - "Antonio Vivaldi: Violin Concerto No. 2..."
    # - "Beethoven - Symphony No. 5"
    # - "Bach, J.S.: Cello Suite No. 1"
    #
    # + title - Titre du morceau ou de l'album
    # + return - Nom du compositeur ou nil si non trouvé
    private function extractComposerFromTitle(string title) returns string? {
        // Pattern 1: "Compositeur: Œuvre" (le plus courant)
        int? colonIndex = title.indexOf(":");
        if colonIndex is int && colonIndex > 2 && colonIndex < 50 {
            string potentialComposer = title.substring(0, colonIndex).trim();
            if self.looksLikeComposerName(potentialComposer) {
                return self.normalizeComposerName(potentialComposer);
            }
        }

        // Pattern 2: "Compositeur - Œuvre"
        int? dashIndex = title.indexOf(" - ");
        if dashIndex is int && dashIndex > 2 && dashIndex < 50 {
            string potentialComposer = title.substring(0, dashIndex).trim();
            if self.looksLikeComposerName(potentialComposer) {
                return self.normalizeComposerName(potentialComposer);
            }
        }

        return ();
    }

    # Extrait le compositeur du nom de l'album
    #
    # + album - Nom de l'album
    # + return - Nom du compositeur ou nil si non trouvé
    private function extractComposerFromAlbum(string album) returns string? {
        return self.extractComposerFromTitle(album);
    }

    # Vérifie si une chaîne ressemble à un nom de compositeur
    #
    # + name - Chaîne à vérifier
    # + return - Vrai si ressemble à un nom de compositeur
    private function looksLikeComposerName(string name) returns boolean {
        // Trop court ou trop long
        if name.length() < 3 || name.length() > 50 {
            return false;
        }

        // Commence par un chiffre (probablement un numéro d'opus)
        string first = name.substring(0, 1);
        if first >= "0" && first <= "9" {
            return false;
        }

        // Contient des mots-clés d'œuvre (pas un nom de compositeur)
        string lower = name.toLowerAscii();
        string[] nonComposerKeywords = [
            "symphony", "concerto", "sonata", "quartet", "trio", "suite",
            "opus", "op.", "no.", "movement", "act", "scene", "variation",
            "allegro", "andante", "adagio", "presto", "largo", "moderato"
        ];

        foreach string keyword in nonComposerKeywords {
            if lower.includes(keyword) {
                return false;
            }
        }

        // Contient au moins un espace (prénom + nom) ou est un nom connu court
        string[] shortComposers = ["bach", "mozart", "haydn", "handel", "verdi", "wagner", "chopin", "liszt", "brahms"];
        foreach string composer in shortComposers {
            if lower == composer {
                return true;
            }
        }

        return name.includes(" ") || name.includes(".");
    }

    # Normalise un nom de compositeur.
    # Ex: "J.S. Bach" -> "Johann Sebastian Bach",
    #     "Beethoven" -> "Ludwig van Beethoven"
    #
    # + name - Nom du compositeur à normaliser
    # + return - Nom complet du compositeur
    private function normalizeComposerName(string name) returns string {
        // Table des noms courts vers noms complets
        map<string> composerFullNames = {
            "bach": "Johann Sebastian Bach",
            "j.s. bach": "Johann Sebastian Bach",
            "j. s. bach": "Johann Sebastian Bach",
            "mozart": "Wolfgang Amadeus Mozart",
            "w.a. mozart": "Wolfgang Amadeus Mozart",
            "beethoven": "Ludwig van Beethoven",
            "haydn": "Joseph Haydn",
            "handel": "George Frideric Handel",
            "vivaldi": "Antonio Vivaldi",
            "a. vivaldi": "Antonio Vivaldi",
            "schubert": "Franz Schubert",
            "brahms": "Johannes Brahms",
            "chopin": "Frédéric Chopin",
            "tchaikovsky": "Pyotr Ilyich Tchaikovsky",
            "debussy": "Claude Debussy",
            "ravel": "Maurice Ravel",
            "stravinsky": "Igor Stravinsky",
            "mahler": "Gustav Mahler",
            "schumann": "Robert Schumann",
            "mendelssohn": "Felix Mendelssohn",
            "liszt": "Franz Liszt",
            "verdi": "Giuseppe Verdi",
            "wagner": "Richard Wagner",
            "puccini": "Giacomo Puccini",
            "dvorak": "Antonín Dvořák",
            "sibelius": "Jean Sibelius",
            "grieg": "Edvard Grieg",
            "rachmaninoff": "Sergei Rachmaninoff",
            "rachmaninov": "Sergei Rachmaninoff",
            "prokofiev": "Sergei Prokofiev",
            "shostakovich": "Dmitri Shostakovich"
        };

        string lower = name.toLowerAscii().trim();
        string? fullName = composerFullNames[lower];
        if fullName is string {
            return fullName;
        }

        // Retourner le nom tel quel s'il n'est pas dans la table
        return name.trim();
    }

    # Détecte si un track est de la musique classique basé sur le titre
    #
    # + title - Titre du morceau
    # + album - Nom de l'album
    # + return - Vrai si musique classique détectée
    private function detectClassicalFromTitle(string title, string album) returns boolean {
        string combined = (title + " " + album).toLowerAscii();

        // Patterns typiques de la musique classique
        string[] classicalPatterns = [
            "symphony", "concerto", "sonata", "quartet", "trio", "quintet",
            "opus", "op.", "bwv", "k.", "hob.", "rv", "woo",
            "allegro", "andante", "adagio", "presto", "largo", "moderato",
            "major", "minor", "flat", "sharp",
            "no. ", "no.", "in c ", "in d ", "in e ", "in f ", "in g ", "in a ", "in b "
        ];

        foreach string pattern in classicalPatterns {
            if combined.includes(pattern) {
                return true;
            }
        }

        return false;
    }

    # Récupère les artistes nécessitant un enrichissement via Claude AI
    #
    # + return - Liste des artistes avec score < seuil
    public function getArtistsNeedingAIEnrichment() returns CachedArtist[] {
        return self.cache.getArtistsNeedingEnrichment(QUALITY_THRESHOLD, 50);
    }

    # Retourne les statistiques du cache
    #
    # + return - Record contenant le nombre d'artistes et de tracks
    public function getCacheStats() returns record {|int artists; int tracks;|} {
        return {
            artists: self.cache.countArtists(),
            tracks: self.cache.countTracks()
        };
    }

    # Enrichit les artistes avec un score faible via Claude AI
    #
    # + maxCalls - Nombre maximum d'appels Claude AI (0 = désactivé, défaut: 50)
    # + return - Nombre d'artistes enrichis
    public function enrichLowScoreArtistsWithAI(int maxCalls = DEFAULT_MAX_CLAUDE_CALLS) returns int|error {
        if maxCalls <= 0 {
            log:printInfo("AI enrichment disabled (aiLimit=0)");
            return 0;
        }

        if self.claudeClient is () {
            log:printWarn("Claude AI client not available, skipping AI enrichment");
            return 0;
        }

        ClaudeClient aiClient = <ClaudeClient>self.claudeClient;
        CachedArtist[] needsEnrichment = self.cache.getArtistsNeedingEnrichment(QUALITY_THRESHOLD, maxCalls);

        int enrichedCount = 0;

        foreach CachedArtist artist in needsEnrichment {
            if self.claudeCallsThisRun >= maxCalls {
                io:println(string `   ⏸️  Limite atteinte (${maxCalls} appels max)`);
                break;
            }

            io:println(string `   🔄 Enrichissement: "${artist.name}" (score actuel: ${artist.qualityScore})...`);

            ClaudeArtistEnrichment|error enrichment = aiClient.enrichArtist(artist.name, artist.genres);
            self.claudeCallsThisRun += 1;

            if enrichment is error {
                io:println(string `   ❌ Échec pour "${artist.name}": ${enrichment.message()}`);
                continue;
            }

            // Valider le composer retourné par Claude AI
            string? validatedComposer = ();
            if enrichment.composerFullName is string {
                // Vérifier que ce n'est pas un nom d'album ou une valeur invalide
                if utils:isValidComposer(enrichment.composerFullName) {
                    validatedComposer = enrichment.composerFullName;
                } else {
                    io:println(string `   ⚠️  Compositeur ignoré (invalide): "${<string>enrichment.composerFullName}"`);
                }
            }
            // Si pas de nouveau composer valide, garder l'ancien s'il est valide
            if validatedComposer is () && artist.composer is string {
                if utils:isValidComposer(artist.composer) {
                    validatedComposer = artist.composer;
                }
            }

            // Vérifier isComposer avec la nouvelle logique si contexte classique
            boolean verifiedIsComposer = enrichment.isComposer;
            string[] updatedGenres = enrichment.genres.length() > 0 ? enrichment.genres : artist.genres;

            // Si Claude dit que c'est un compositeur ET qu'on est dans un contexte classique,
            // faire une vérification plus stricte
            if enrichment.isComposer && utils:isClassicalContext(updatedGenres) {
                // Utiliser la vérification binaire pour confirmer
                if self.claudeCallsThisRun < maxCalls {
                    boolean|error composerCheck = self.verifyIsComposerWithAI(artist, maxCalls);
                    if composerCheck is boolean {
                        verifiedIsComposer = composerCheck;
                        if !verifiedIsComposer && enrichment.isComposer {
                            io:println(string `   🔄 isComposer corrigé: false (était true)`);
                        }
                    }
                }
            } else if !enrichment.isComposer && utils:isClassicalContext(updatedGenres) {
                // Si Claude dit que ce n'est pas un compositeur mais qu'on est dans un contexte classique,
                // vérifier quand même (cas de compositeurs mal détectés comme J.S. Bach)
                if self.claudeCallsThisRun < maxCalls {
                    boolean|error composerCheck = self.verifyIsComposerWithAI(artist, maxCalls);
                    if composerCheck is boolean {
                        verifiedIsComposer = composerCheck;
                        if verifiedIsComposer && !enrichment.isComposer {
                            io:println(string `   🔄 isComposer corrigé: true (était false)`);
                        }
                    }
                }
            }

            // Mettre à jour l'artiste avec les nouvelles informations
            CachedArtist updatedArtist = {
                name: artist.name,
                nameNormalized: utils:normalizeString(artist.name),
                mbid: artist.mbid,
                genres: updatedGenres,
                composer: validatedComposer,
                isComposer: verifiedIsComposer,
                qualityScore: self.calculateEnrichedScore(enrichment, artist),
                enrichmentSource: "claude",
                lastUpdated: self.cache.getCurrentTimestamp(),
                enrichedByAI: true,
                canonicalArtistId: artist.canonicalArtistId
            };

            check self.cache.saveArtist(updatedArtist);
            enrichedCount += 1;

            // Affichage clair du résultat
            io:println(string `   ✅ "${artist.name}" enrichi via Claude AI`);
            io:println(string `      Genres: ${updatedArtist.genres.toString()}`);
            io:println(string `      Nouveau score: ${updatedArtist.qualityScore}`);
            if updatedArtist.composer is string {
                io:println(string `      Compositeur: ${<string>updatedArtist.composer}`);
            }
        }

        return enrichedCount;
    }

    # Calcule le score après enrichissement Claude AI
    #
    # + enrichment - Données d'enrichissement de Claude
    # + original - Artiste original avant enrichissement
    # + return - Score de qualité calculé (0.0 à 1.0)
    private function calculateEnrichedScore(ClaudeArtistEnrichment enrichment, CachedArtist original) returns decimal {
        decimal score = 0.0d;

        // Genres (max 0.4)
        if enrichment.genres.length() > 0 {
            score += enrichment.genres.length() >= 2 ? 0.4d : 0.2d;
        }

        // Type de musique identifié (0.2)
        if enrichment.musicType is string {
            score += 0.2d;
        }

        // Compositeur identifié (0.2)
        if enrichment.isComposer || enrichment.composerFullName is string {
            score += 0.2d;
        }

        // Description disponible (0.1)
        if enrichment.description is string {
            score += 0.1d;
        }

        // Bonus pour enrichissement AI réussi (0.1)
        score += 0.1d;

        return score > 1.0d ? 1.0d : score;
    }

    # Retourne le nombre d'appels Claude AI restants pour cette exécution
    #
    # + maxCalls - Limite maximum configurée
    # + return - Nombre d'appels restants
    public function getRemainingClaudeCalls(int maxCalls = DEFAULT_MAX_CLAUDE_CALLS) returns int {
        return maxCalls - self.claudeCallsThisRun;
    }

    # Retourne l'instance du cache pour un accès direct
    #
    # + return - Instance du cache
    public function getCache() returns CacheDb {
        return self.cache;
    }

    # Récupère tous les artistes du cache
    #
    # + return - Liste de tous les artistes en cache
    public function getAllCachedArtists() returns CachedArtist[] {
        return self.cache.getAllArtists();
    }

    # Récupère tous les tracks du cache
    #
    # + return - Liste de tous les tracks en cache
    public function getAllCachedTracks() returns CachedTrack[] {
        return self.cache.getAllTracks();
    }

    # Enrichit un track classique avec les métadonnées détaillées via Claude AI
    # Utilise le prompt spécialisé pour identifier compositeur, période, forme, catalogue
    #
    # + artistName - Nom de l'artiste/interprète
    # + trackName - Nom du morceau
    # + albumName - Nom de l'album (optionnel)
    # + maxCalls - Limite d'appels AI restants
    # + return - Track enrichi ou nil si pas de client AI
    public function enrichClassicalTrackWithAI(string artistName, string trackName, string? albumName = (),
            int maxCalls = DEFAULT_MAX_CLAUDE_CALLS) returns CachedTrack?|error {

        if self.claudeClient is () {
            log:printDebug("Claude AI not available for classical track enrichment");
            return ();
        }

        if self.claudeCallsThisRun >= maxCalls {
            log:printDebug("AI call limit reached for classical track enrichment");
            return ();
        }

        ClaudeClient aiClient = <ClaudeClient>self.claudeClient;

        io:println(string `   🎼 Enrichissement classique: "${trackName}" par "${artistName}"...`);

        ClaudeClassicalEnrichment|error enrichment = aiClient.enrichClassicalTrack(artistName, trackName, albumName);
        self.claudeCallsThisRun += 1;

        if enrichment is error {
            io:println(string `   ❌ Échec enrichissement classique: ${enrichment.message()}`);
            return ();
        }

        // Vérifier la confiance
        if enrichment.confidence is decimal {
            decimal conf = <decimal>enrichment.confidence;
            if conf < 0.5d {
                io:println(string `   ⚠️  Confiance trop basse (${conf}), ignoré`);
                return ();
            }
        }

        // Valider le composer
        string? validatedComposer = ();
        if enrichment.composer is string {
            if utils:isValidComposer(enrichment.composer, albumName) {
                validatedComposer = enrichment.composer;
            }
        }

        // Calculer le score
        decimal qualityScore = self.calculateClassicalTrackScore(enrichment);

        // Créer le track enrichi
        CachedTrack cachedTrack = {
            artistName: artistName,
            trackName: trackName,
            albumName: albumName,
            genres: ["classical"],
            composer: validatedComposer,
            qualityScore: qualityScore,
            enrichmentSource: "claude",
            period: enrichment.period,
            musicalForm: enrichment.musicalForm,
            opusCatalog: enrichment.opusCatalog,
            workTitle: enrichment.workTitle,
            movement: enrichment.movement,
            lastUpdated: self.cache.getCurrentTimestamp()
        };

        // Sauvegarder
        check self.cache.saveTrack(cachedTrack);

        // Affichage
        io:println(string `   ✅ Track classique enrichi`);
        if validatedComposer is string {
            io:println(string `      Compositeur: ${validatedComposer}`);
        }
        if enrichment.period is string {
            io:println(string `      Période: ${<string>enrichment.period}`);
        }
        if enrichment.opusCatalog is string {
            io:println(string `      Catalogue: ${<string>enrichment.opusCatalog}`);
        }

        return cachedTrack;
    }

    # Vérifie si un artiste est un compositeur historique via Claude AI
    # Utilise une question binaire claire pour éviter les faux positifs
    #
    # + artist - Artiste à vérifier
    # + maxCalls - Limite d'appels AI restants
    # + return - true si compositeur historique, false sinon
    public function verifyIsComposerWithAI(CachedArtist artist, int maxCalls = DEFAULT_MAX_CLAUDE_CALLS) returns boolean|error {
        if self.claudeClient is () {
            return artist.isComposer; // Garder la valeur actuelle
        }

        if self.claudeCallsThisRun >= maxCalls {
            return artist.isComposer;
        }

        // Ne vérifier que si c'est un candidat potentiel (genres classiques)
        if !utils:isClassicalContext(artist.genres) {
            return false; // Pas dans un contexte classique = pas un compositeur historique
        }

        ClaudeClient aiClient = <ClaudeClient>self.claudeClient;

        io:println(string `   🔍 Vérification compositeur: "${artist.name}"...`);

        ClaudeComposerCheck|error checkResult = aiClient.checkIsComposer(artist.name, artist.genres);
        self.claudeCallsThisRun += 1;

        if checkResult is error {
            io:println(string `   ❌ Échec vérification: ${checkResult.message()}`);
            return artist.isComposer;
        }

        if checkResult.isHistoricalComposer {
            io:println(string `   ✅ "${artist.name}" est un compositeur historique`);
        } else {
            io:println(string `   ℹ️  "${artist.name}" est un interprète/ensemble`);
        }
        if checkResult.explanation is string {
            io:println(string `      ${<string>checkResult.explanation}`);
        }

        return checkResult.isHistoricalComposer;
    }

    # Calcule le score pour un track classique enrichi
    #
    # + enrichment - Données d'enrichissement classique
    # + return - Score de qualité (0.0 à 1.0)
    private function calculateClassicalTrackScore(ClaudeClassicalEnrichment enrichment) returns decimal {
        decimal score = 0.0d;

        // Compositeur identifié (0.3)
        if enrichment.composer is string {
            score += 0.3d;
        }

        // Période identifiée (0.15)
        if enrichment.period is string {
            score += 0.15d;
        }

        // Forme musicale identifiée (0.15)
        if enrichment.musicalForm is string {
            score += 0.15d;
        }

        // Catalogue identifié (0.2)
        if enrichment.opusCatalog is string {
            score += 0.2d;
        }

        // Titre d'oeuvre identifié (0.1)
        if enrichment.workTitle is string {
            score += 0.1d;
        }

        // Mouvement identifié (0.05)
        if enrichment.movement is string {
            score += 0.05d;
        }

        // Bonus confiance (0.05)
        if enrichment.confidence is decimal && <decimal>enrichment.confidence >= 0.8d {
            score += 0.05d;
        }

        return score > 1.0d ? 1.0d : score;
    }

    # Enrichit les tracks classiques qui n'ont pas encore de compositeur identifié
    #
    # + maxCalls - Nombre maximum d'appels Claude AI
    # + return - Nombre de tracks enrichis
    public function enrichClassicalTracksWithAI(int maxCalls = DEFAULT_MAX_CLAUDE_CALLS) returns int|error {
        if maxCalls <= 0 || self.claudeClient is () {
            return 0;
        }

        // Récupérer les tracks qui semblent classiques mais sans compositeur
        CachedTrack[] allTracks = self.cache.getAllTracks();
        int enrichedCount = 0;

        foreach CachedTrack track in allTracks {
            if self.claudeCallsThisRun >= maxCalls {
                io:println(string `   ⏸️  Limite atteinte pour enrichissement classique`);
                break;
            }

            // Skip si déjà enrichi par Claude ou si a déjà un compositeur
            if track.enrichmentSource == "claude" || track.composer is string {
                continue;
            }

            // Vérifier si le track semble classique (par genres ou titre)
            boolean seemsClassical = utils:isClassicalContext(track.genres)
                || self.detectClassicalFromTitle(track.trackName, track.albumName ?: "");

            if !seemsClassical {
                continue;
            }

            // Enrichir
            CachedTrack?|error enriched = check self.enrichClassicalTrackWithAI(
                track.artistName, track.trackName, track.albumName, maxCalls
            );

            if enriched is CachedTrack {
                enrichedCount += 1;
            }
        }

        return enrichedCount;
    }
}
