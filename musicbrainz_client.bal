import ballerina/http;
import ballerina/log;

# Configuration du client MusicBrainz
#
# + baseUrl - URL de base de l'API MusicBrainz
# + userAgent - User-Agent pour les requêtes HTTP
public type MusicBrainzConfig record {|
    string baseUrl = "https://musicbrainz.org/ws/2";
    string userAgent = "LastFmHistoryApp/0.1 (contact@example.com)";
|};

# Informations enrichies d'un artiste
#
# + mbid - MusicBrainz ID
# + name - Nom de l'artiste
# + type - Type d'artiste (Person, Group, Orchestra, etc.)
# + disambiguation - Texte de désambiguïsation
# + genres - Liste des genres musicaux
# + tags - Liste des tags MusicBrainz
# + isComposer - Indique si l'artiste est un compositeur
# + qualityScore - Score de qualité des données (0.0 à 1.0)
public type ArtistInfo record {|
    string mbid;
    string name;
    string? 'type;
    string? disambiguation;
    string[] genres;
    string[] tags;
    boolean isComposer;
    decimal qualityScore;
|};

# Informations enrichies d'un recording
#
# + mbid - MusicBrainz ID
# + title - Titre du morceau
# + composer - Nom du compositeur (si applicable)
# + performer - Nom de l'interprète
# + genres - Liste des genres musicaux
# + qualityScore - Score de qualité des données (0.0 à 1.0)
public type RecordingInfo record {|
    string mbid;
    string title;
    string? composer;
    string? performer;
    string[] genres;
    decimal qualityScore;
|};

# Client pour l'API MusicBrainz
public isolated class MusicBrainzClient {

    private final http:Client httpClient;
    private final string userAgent;

    public function init(MusicBrainzConfig config = {}) returns error? {
        self.userAgent = config.userAgent;
        self.httpClient = check new (config.baseUrl, {
            httpVersion: http:HTTP_1_1,
            timeout: 30
        });
    }

    # Recherche un artiste par son mbid
    #
    # + mbid - MusicBrainz ID de l'artiste
    # + return - Informations de l'artiste ou erreur
    public function getArtistByMbid(string mbid) returns ArtistInfo|error {
        if mbid == "" {
            return error("mbid is empty");
        }

        string path = string `/artist/${mbid}?fmt=json&inc=tags+genres`;

        log:printDebug(string `MusicBrainz API call: artist/${mbid}`);

        map<string> headers = {"User-Agent": self.userAgent};
        json response = check self.httpClient->get(path, headers);

        return self.parseArtistResponse(response);
    }

    # Recherche un artiste par son nom avec parsing intelligent
    #
    # + artistName - Nom de l'artiste à rechercher
    # + return - Informations de l'artiste ou erreur
    public function searchArtist(string artistName) returns ArtistInfo|error {
        // Parser le nom pour extraire les différentes parties
        string[] nameParts = self.parseArtistName(artistName);

        // Essayer chaque partie du nom jusqu'à trouver un résultat
        foreach string namePart in nameParts {
            ArtistInfo|error result = self.searchArtistDirect(namePart);
            if result is ArtistInfo && result.qualityScore > 0.0d {
                log:printInfo(string `Found artist "${namePart}" from "${artistName}"`);
                return result;
            }
        }

        // Fallback: recherche directe avec le nom complet
        return self.searchArtistDirect(artistName);
    }

    # Recherche directe d'un artiste sur MusicBrainz.
    # Étape 1: Recherche par nom pour obtenir le mbid.
    # Étape 2: Lookup par mbid avec inc=tags+genres pour les métadonnées complètes.
    #
    # + artistName - Nom de l'artiste à rechercher
    # + return - Informations de l'artiste ou erreur
    private function searchArtistDirect(string artistName) returns ArtistInfo|error {
        string encodedName = self.urlEncode(artistName);
        string path = string `/artist/?query=${encodedName}&fmt=json&limit=1`;

        log:printDebug(string `MusicBrainz search: ${artistName}`);

        map<string> headers = {"User-Agent": self.userAgent};
        json response = check self.httpClient->get(path, headers);

        // Extraire le premier résultat
        json[] artists = check response.artists.ensureType();
        if artists.length() == 0 {
            return error(string `Artist not found: ${artistName}`);
        }

        // Extraire le mbid du résultat de recherche
        map<json> firstArtist = check artists[0].ensureType();
        string mbid = (check firstArtist["id"]).toString();

        // Faire un lookup par mbid pour obtenir les tags et genres
        log:printDebug(string `MusicBrainz lookup by mbid: ${mbid}`);
        return self.getArtistByMbid(mbid);
    }

    # Parse un nom d'artiste composé pour extraire les différentes parties.
    # Ex: "Holland Baroque Society / Rachel Podger (violin)"
    #     -> ["Rachel Podger", "Holland Baroque Society"]
    #
    # + artistName - Nom complet de l'artiste à parser
    # + return - Liste des parties du nom triées par longueur
    private function parseArtistName(string artistName) returns string[] {
        string[] parts = [];

        // Supprimer les annotations entre parenthèses (violin), (piano), etc.
        string cleanName = re `\s*\([^)]*\)\s*`.replaceAll(artistName, "");

        // Séparer par les séparateurs courants
        // On fait plusieurs passes pour gérer tous les cas
        string[] segments = self.splitByMultipleSeparators(cleanName);

        // Collecter les segments valides
        foreach string segment in segments {
            string trimmed = segment.trim();
            if trimmed.length() > 2 {
                parts.push(trimmed);
            }
        }

        // Trier: noms plus courts en premier (souvent l'artiste principal)
        int n = parts.length();
        foreach int i in 0 ..< n - 1 {
            foreach int j in 0 ..< n - i - 1 {
                if parts[j].length() > parts[j + 1].length() {
                    string temp = parts[j];
                    parts[j] = parts[j + 1];
                    parts[j + 1] = temp;
                }
            }
        }

        return parts;
    }

    # Sépare une chaîne par plusieurs séparateurs
    #
    # + input - Chaîne à séparer
    # + return - Liste des segments
    private function splitByMultipleSeparators(string input) returns string[] {
        // Remplacer tous les séparateurs par un délimiteur unique
        string normalized = input;
        normalized = re ` / `.replaceAll(normalized, "|||");
        normalized = re ` & `.replaceAll(normalized, "|||");
        normalized = re `, `.replaceAll(normalized, "|||");
        normalized = re `; `.replaceAll(normalized, "|||");
        normalized = re ` feat\. `.replaceAll(normalized, "|||");
        normalized = re ` feat `.replaceAll(normalized, "|||");
        normalized = re ` ft\. `.replaceAll(normalized, "|||");
        normalized = re ` ft `.replaceAll(normalized, "|||");

        // Séparer par le délimiteur unique
        return re `\|\|\|`.split(normalized);
    }

    # Parse la réponse JSON d'un artiste
    #
    # + artistJson - Réponse JSON de l'API MusicBrainz
    # + return - Informations de l'artiste ou erreur
    private function parseArtistResponse(json artistJson) returns ArtistInfo|error {
        map<json> artist = check artistJson.ensureType();

        string mbid = (check artist["id"]).toString();
        string name = (check artist["name"]).toString();
        string? artistType = artist["type"] is () ? () : artist["type"].toString();
        string? disambiguation = artist["disambiguation"] is () ? () : artist["disambiguation"].toString();

        // Extraire les tags
        string[] tags = [];
        string[] genres = [];
        boolean isComposer = false;

        if artist.hasKey("tags") && !(artist["tags"] is ()) {
            json[]|error tagsArray = artist["tags"].ensureType();
            if tagsArray is json[] {
                foreach json tagJson in tagsArray {
                    map<json>|error tagMap = tagJson.ensureType();
                    if tagMap is map<json> {
                        string tagName = tagMap["name"].toString().toLowerAscii();
                        int|error count = tagMap["count"].ensureType();

                        // Ne garder que les tags avec un score positif
                        if count is int && count >= 0 {
                            tags.push(tagName);

                            // Détecter si c'est un compositeur
                            if tagName == "composer" || tagName.includes("composer") {
                                isComposer = true;
                            }

                            // Identifier les genres musicaux principaux
                            if self.isGenreTag(tagName) {
                                genres.push(tagName);
                            }
                        }
                    }
                }
            }
        }

        // Extraire les genres officiels si présents
        if artist.hasKey("genres") && !(artist["genres"] is ()) {
            json[]|error genresArray = artist["genres"].ensureType();
            if genresArray is json[] {
                foreach json genreJson in genresArray {
                    map<json>|error genreMap = genreJson.ensureType();
                    if genreMap is map<json> {
                        string genreName = genreMap["name"].toString().toLowerAscii();
                        if genres.indexOf(genreName) is () {
                            genres.push(genreName);
                        }
                    }
                }
            }
        }

        // Calculer le score de qualité
        decimal qualityScore = self.calculateArtistQualityScore(genres, tags, isComposer, disambiguation);

        return {
            mbid: mbid,
            name: name,
            'type: artistType,
            disambiguation: disambiguation,
            genres: genres,
            tags: tags,
            isComposer: isComposer,
            qualityScore: qualityScore
        };
    }

    # Détermine si un tag est un genre musical
    #
    # + tag - Tag à vérifier
    # + return - Vrai si le tag est un genre musical
    private function isGenreTag(string tag) returns boolean {
        string[] genreKeywords = [
            "classical", "romantic", "baroque", "renaissance", "medieval",
            "rock", "pop", "jazz", "blues", "electronic", "electro",
            "metal", "punk", "hip-hop", "rap", "r&b", "soul", "funk",
            "country", "folk", "reggae", "ska", "world", "latin",
            "ambient", "experimental", "avant-garde", "new age",
            "opera", "choral", "symphony", "chamber music"
        ];

        foreach string genre in genreKeywords {
            if tag.includes(genre) {
                return true;
            }
        }
        return false;
    }

    # Calcule le score de qualité des données d'un artiste.
    # Critères:
    # - Genres trouvés: +0.4 (max)
    # - Tags trouvés: +0.2 (max)
    # - isComposer déterminé: +0.2
    # - Disambiguation présent: +0.2
    #
    # + genres - Liste des genres trouvés
    # + tags - Liste des tags trouvés
    # + isComposer - Indique si l'artiste est un compositeur
    # + disambiguation - Texte de désambiguïsation
    # + return - Score de qualité (0.0 à 1.0)
    private function calculateArtistQualityScore(
            string[] genres,
            string[] tags,
            boolean isComposer,
            string? disambiguation
    ) returns decimal {
        decimal score = 0.0d;

        // Genres (max 0.4)
        if genres.length() > 0 {
            score += genres.length() >= 2 ? 0.4d : 0.2d;
        }

        // Tags (max 0.2)
        if tags.length() > 0 {
            score += tags.length() >= 3 ? 0.2d : 0.1d;
        }

        // Compositeur identifié
        if isComposer {
            score += 0.2d;
        }

        // Disambiguation présent
        if disambiguation is string && disambiguation.length() > 0 {
            score += 0.2d;
        }

        return score > 1.0d ? 1.0d : score;
    }

    # Encode une chaîne pour l'URL
    #
    # + input - Chaîne à encoder
    # + return - Chaîne encodée pour URL
    private function urlEncode(string input) returns string {
        // Encodage simplifié - remplacer les espaces et caractères spéciaux
        string result = input;
        result = re `\s+`.replaceAll(result, "%20");
        result = re `&`.replaceAll(result, "%26");
        result = re `\+`.replaceAll(result, "%2B");
        return result;
    }
}