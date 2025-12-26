import ballerina/log;

# Seuil de qualité pour déclencher l'enrichissement via Claude AI
const decimal QUALITY_THRESHOLD = 0.8d;

# Track enrichi avec métadonnées complètes
public type EnrichedTrack record {|
    string timestamp?;
    string datetime?;
    string artist;
    string track;
    string album;
    boolean loved;
    boolean nowPlaying;
    // Métadonnées enrichies
    string[] genres;
    string? composer;
    boolean isClassical;
    decimal qualityScore;
|};

# Service d'enrichissement des données musicales
public class EnrichmentService {

    private final MusicBrainzClient mbClient;
    private final CacheDb cache;

    public function init() returns error? {
        self.mbClient = check new ();
        self.cache = check new ();
        log:printInfo("Enrichment service initialized");
    }

    # Enrichit une liste de tracks avec les métadonnées MusicBrainz
    #
    # + tracks - Liste des tracks à enrichir
    # + return - Liste des tracks enrichis
    public function enrichTracks(SimpleTrack[] tracks) returns EnrichedTrack[]|error {
        EnrichedTrack[] enrichedTracks = [];

        foreach SimpleTrack track in tracks {
            EnrichedTrack enriched = check self.enrichTrack(track);
            enrichedTracks.push(enriched);
        }

        return enrichedTracks;
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
            log:printDebug(string `Cache hit: ${artistName}`);
            return cached;
        }

        // 2. Rechercher sur MusicBrainz
        log:printDebug(string `Cache miss, fetching from MusicBrainz: ${artistName}`);
        ArtistInfo|error mbInfo = self.mbClient.searchArtist(artistName);

        if mbInfo is error {
            log:printWarn(string `MusicBrainz lookup failed for: ${artistName} - ${mbInfo.message()}`);
            // Créer une entrée avec score bas pour réessayer plus tard
            CachedArtist fallback = {
                name: artistName,
                mbid: (),
                genres: [],
                composer: (),
                isComposer: false,
                qualityScore: 0.0d,
                lastUpdated: self.cache.getCurrentTimestamp()
            };
            check self.cache.saveArtist(fallback);
            return fallback;
        }

        // 3. Sauvegarder dans le cache
        CachedArtist cachedArtist = self.cache.createCachedArtist(mbInfo);
        check self.cache.saveArtist(cachedArtist);

        log:printInfo(string `Enriched artist: ${artistName} (genres: ${mbInfo.genres.toString()}, score: ${mbInfo.qualityScore})`);

        return cachedArtist;
    }

    # Détermine si c'est de la musique classique
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

    # Extrait le compositeur du titre du track ou de l'album
    # Patterns reconnus:
    # - "Antonio Vivaldi: Violin Concerto No. 2..."
    # - "Beethoven - Symphony No. 5"
    # - "Bach, J.S.: Cello Suite No. 1"
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
    private function extractComposerFromAlbum(string album) returns string? {
        return self.extractComposerFromTitle(album);
    }

    # Vérifie si une chaîne ressemble à un nom de compositeur
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

    # Normalise un nom de compositeur
    # Ex: "J.S. Bach" -> "Johann Sebastian Bach"
    #     "Beethoven" -> "Ludwig van Beethoven"
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
    public function getCacheStats() returns record {|int artists; int tracks;|} {
        return {
            artists: self.cache.countArtists(),
            tracks: self.cache.countTracks()
        };
    }
}
