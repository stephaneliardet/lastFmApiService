import ballerina/http;
import ballerina/log;

# Configuration du client Claude AI
configurable string claudeApiKey = ?;

# Configuration du client Claude
#
# + baseUrl - URL de base de l'API Anthropic
# + model - Modèle Claude à utiliser
# + maxTokens - Nombre maximum de tokens en réponse
public type ClaudeConfig record {|
    string baseUrl = "https://api.anthropic.com/v1";
    string model = "claude-sonnet-4-20250514";
    int maxTokens = 1024;
|};

# Réponse d'enrichissement d'artiste par Claude
#
# + genres - Liste des genres musicaux identifiés
# + isComposer - Indique si l'artiste est principalement un compositeur
# + composerFullName - Nom complet du compositeur (pour la musique classique)
# + musicType - Type de musique (classical, jazz, rock, pop, etc.)
# + era - Période musicale (baroque, romantic, modern, contemporary, etc.)
# + description - Courte description de l'artiste
public type ClaudeArtistEnrichment record {|
    string[] genres;
    boolean isComposer;
    string? composerFullName;
    string? musicType;
    string? era;
    string? description;
|};

# Réponse d'enrichissement de track classique par Claude
#
# + composer - Nom complet du compositeur historique
# + period - Période musicale (renaissance, baroque, classical, romantic, modern, contemporary)
# + musicalForm - Forme musicale (symphony, concerto, sonata, cantata, opera, etc.)
# + opusCatalog - Numéro de catalogue (BWV 1001, K. 466, Op. 12, SV 139, etc.)
# + workTitle - Titre normalisé de l'oeuvre complète (sans le mouvement)
# + movement - Mouvement si applicable (I. Allegro, II. Andante, etc.)
# + confidence - Score de confiance (0.0 à 1.0)
public type ClaudeClassicalEnrichment record {|
    string? composer;
    string? period;
    string? musicalForm;
    string? opusCatalog;
    string? workTitle;
    string? movement;
    decimal? confidence;
|};

# Réponse pour la question is_composer (A ou B)
#
# + isHistoricalComposer - true si compositeur historique (réponse A)
# + explanation - Courte explication
public type ClaudeComposerCheck record {|
    boolean isHistoricalComposer;
    string? explanation;
|};

# Client pour l'API Claude AI
public isolated class ClaudeClient {

    private final http:Client httpClient;
    private final string apiKey;
    private final string model;
    private final int maxTokens;

    public function init(ClaudeConfig config = {}) returns error? {
        // Vérifier que la clé API est configurée
        if claudeApiKey.trim().length() == 0 {
            return error("Claude API key is not configured");
        }

        self.apiKey = claudeApiKey;
        self.model = config.model;
        self.maxTokens = config.maxTokens;
        self.httpClient = check new (config.baseUrl, {
            httpVersion: http:HTTP_1_1,
            timeout: 60
        });
        log:printInfo(string `Claude AI client initialized (model: ${self.model})`);
    }

    # Enrichit les informations d'un artiste via Claude AI
    #
    # + artistName - Nom de l'artiste
    # + existingGenres - Genres déjà connus (depuis MusicBrainz)
    # + return - Informations enrichies ou erreur
    public function enrichArtist(string artistName, string[] existingGenres = []) returns ClaudeArtistEnrichment|error {
        string existingInfo = existingGenres.length() > 0
            ? string `Genres déjà connus: ${existingGenres.toString()}`
            : "Aucun genre connu";

        string prompt = string `Tu es un expert en musique. Analyse l'artiste "${artistName}".
${existingInfo}

Réponds UNIQUEMENT avec un objet JSON valide (sans markdown, sans backticks) avec cette structure exacte:
{
    "genres": ["genre1", "genre2"],
    "isComposer": true/false,
    "composerFullName": "nom complet si compositeur classique, sinon null",
    "musicType": "classical/jazz/rock/pop/electronic/folk/world/other",
    "era": "baroque/classical/romantic/modern/contemporary/null si non applicable",
    "description": "courte description de l'artiste (1 phrase)"
}

Règles:
- genres: liste de 2-5 genres musicaux en anglais, du plus spécifique au plus général
- isComposer: true si c'est principalement un compositeur (musique classique, film, etc.)
- composerFullName: nom complet uniquement pour les compositeurs classiques (ex: "Johann Sebastian Bach")
- musicType: catégorie principale
- era: période musicale (surtout pour la musique classique)
- description: en français, 1 phrase maximum`;

        json response = check self.callClaude(prompt);
        return self.parseEnrichmentResponse(response);
    }

    # Appelle l'API Claude
    #
    # + prompt - Texte du prompt à envoyer
    # + return - Réponse JSON ou erreur
    private function callClaude(string prompt) returns json|error {
        json requestBody = {
            "model": self.model,
            "max_tokens": self.maxTokens,
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ]
        };

        map<string> headers = {
            "x-api-key": self.apiKey,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json"
        };

        log:printDebug("Calling Claude AI API...");

        http:Response response = check self.httpClient->post("/messages", requestBody, headers);

        if response.statusCode != 200 {
            string errorBody = check response.getTextPayload();
            log:printError(string `Claude API error: ${response.statusCode} - ${errorBody}`);
            return error(string `Claude API error: ${response.statusCode}`);
        }

        json responseJson = check response.getJsonPayload();
        return responseJson;
    }

    # Parse la réponse de Claude pour extraire l'enrichissement
    #
    # + response - Réponse JSON brute de l'API Claude
    # + return - Enrichissement parsé ou erreur
    private function parseEnrichmentResponse(json response) returns ClaudeArtistEnrichment|error {
        // Extraire le contenu texte de la réponse
        json[] content = check response.content.ensureType();
        if content.length() == 0 {
            return error("Empty response from Claude");
        }

        map<json> firstContent = check content[0].ensureType();
        string textContent = (check firstContent["text"]).toString();

        // Parser le JSON dans la réponse
        // Nettoyer le texte (enlever les backticks markdown si présents)
        string cleanJson = textContent;
        if cleanJson.startsWith("```json") {
            cleanJson = cleanJson.substring(7);
        } else if cleanJson.startsWith("```") {
            cleanJson = cleanJson.substring(3);
        }
        if cleanJson.endsWith("```") {
            cleanJson = cleanJson.substring(0, cleanJson.length() - 3);
        }
        cleanJson = cleanJson.trim();

        json parsed = check cleanJson.fromJsonString();
        map<json> data = check parsed.ensureType();

        // Extraire les genres
        string[] genres = [];
        json[]|error genresArray = data["genres"].ensureType();
        if genresArray is json[] {
            foreach json g in genresArray {
                genres.push(g.toString());
            }
        }

        // Extraire isComposer
        boolean isComposer = false;
        boolean|error isComp = data["isComposer"].ensureType();
        if isComp is boolean {
            isComposer = isComp;
        }

        // Extraire les champs optionnels
        string? composerFullName = data["composerFullName"] is () ? () : data["composerFullName"].toString();
        if composerFullName == "null" {
            composerFullName = ();
        }

        string? musicType = data["musicType"] is () ? () : data["musicType"].toString();
        if musicType == "null" {
            musicType = ();
        }

        string? era = data["era"] is () ? () : data["era"].toString();
        if era == "null" {
            era = ();
        }

        string? description = data["description"] is () ? () : data["description"].toString();
        if description == "null" {
            description = ();
        }

        return {
            genres: genres,
            isComposer: isComposer,
            composerFullName: composerFullName,
            musicType: musicType,
            era: era,
            description: description
        };
    }

    # Enrichit un track de musique classique/baroque via Claude AI
    # Utilise un prompt spécialisé pour identifier compositeur, période, forme, catalogue
    #
    # + artistName - Nom de l'artiste/interprète
    # + trackName - Nom du morceau
    # + albumName - Nom de l'album (optionnel)
    # + return - Informations enrichies ou erreur
    public function enrichClassicalTrack(string artistName, string trackName, string? albumName = ())
            returns ClaudeClassicalEnrichment|error {

        string albumInfo = albumName is string ? string `de l'album "${albumName}"` : "";

        string prompt = string `Tu es un expert en musique classique et baroque.

L'artiste "${artistName}" est un interprète ou ensemble de musique classique/baroque.
Le morceau "${trackName}" ${albumInfo} est probablement une œuvre d'un compositeur historique.

Identifie avec précision:
1. Le compositeur original de cette œuvre (pas l'interprète)
2. La période musicale: renaissance, baroque, classical, romantic, modern, contemporary
3. La forme musicale: symphony, concerto, sonata, cantata, opera, oratorio, quartet, trio, quintet, suite, partita, mass, motet, magnificat, passion, aria, lied, madrigal, prelude, fugue, toccata, fantasia, etude, variations, sinfonia, overture, divertimento, serenade, other
4. Le numéro de catalogue si présent (BWV, HWV, K., KV, Op., Wq., SV, RV, D., L., S., etc.)
5. Le titre normalisé de l'œuvre (sans le mouvement)
6. Le mouvement si applicable

Indices de catalogues:
- "SV" = Monteverdi
- "BWV" = J.S. Bach
- "HWV" = Handel
- "K." ou "KV" = Mozart
- "Wq." = C.P.E. Bach
- "Op." = numéro d'opus générique
- "RV" = Vivaldi
- "D." = Schubert
- "L." = Debussy
- "S." = Liszt

Réponds UNIQUEMENT avec un objet JSON valide (sans markdown, sans backticks):
{
    "composer": "Nom complet du compositeur ou null si non identifiable",
    "period": "baroque/classical/romantic/modern/contemporary/renaissance ou null",
    "musicalForm": "symphony/concerto/sonata/etc. ou null",
    "opusCatalog": "BWV 1001/K. 466/Op. 12 ou null",
    "workTitle": "Titre normalisé de l'œuvre ou null",
    "movement": "I. Allegro/II. Andante ou null",
    "confidence": 0.0 à 1.0
}

Si tu n'es pas sûr qu'il s'agisse de musique classique, retourne tous les champs à null avec confidence: 0.0`;

        json response = check self.callClaude(prompt);
        return self.parseClassicalEnrichmentResponse(response);
    }

    # Vérifie si un artiste est un compositeur historique via Claude AI
    # Utilise une question binaire claire pour éviter les faux positifs
    #
    # + artistName - Nom de l'artiste
    # + genres - Genres connus de l'artiste
    # + return - Résultat de la vérification ou erreur
    public function checkIsComposer(string artistName, string[] genres = []) returns ClaudeComposerCheck|error {
        string genreInfo = genres.length() > 0
            ? string `Genres connus: ${genres.toString()}`
            : "";

        string prompt = string `Tu es un expert en musique classique.

"${artistName}" est-il :
A) Un compositeur historique dont les œuvres sont interprétées par d'autres (ex: Bach, Mozart, Vivaldi, Monteverdi, Beethoven)
B) Un interprète, ensemble, orchestre ou artiste contemporain qui performe ses propres créations ou celles d'autres

${genreInfo}

Critères pour répondre A (compositeur historique):
- Généralement décédé depuis longtemps
- Ses œuvres font partie du répertoire classique
- D'autres artistes/ensembles interprètent régulièrement ses compositions

Critères pour répondre B (interprète/contemporain):
- Un ensemble baroque (ex: "Il Giardino Armonico") n'est PAS un compositeur même s'il joue du baroque
- Un artiste contemporain qui compose sa propre musique (ex: "Émilie Simon") n'est PAS un "compositeur" au sens classique
- Un pianiste, violoniste, chef d'orchestre qui interprète des œuvres n'est PAS un compositeur

Réponds UNIQUEMENT avec un objet JSON valide (sans markdown, sans backticks):
{
    "answer": "A" ou "B",
    "explanation": "courte explication en français (1 phrase)"
}`;

        json response = check self.callClaude(prompt);
        return self.parseComposerCheckResponse(response);
    }

    # Parse la réponse de Claude pour l'enrichissement classique
    #
    # + response - Réponse JSON brute de l'API Claude
    # + return - Enrichissement classique parsé ou erreur
    private function parseClassicalEnrichmentResponse(json response) returns ClaudeClassicalEnrichment|error {
        // Extraire le contenu texte de la réponse
        json[] content = check response.content.ensureType();
        if content.length() == 0 {
            return error("Empty response from Claude");
        }

        map<json> firstContent = check content[0].ensureType();
        string textContent = (check firstContent["text"]).toString();

        // Nettoyer et parser le JSON
        string cleanJson = self.cleanJsonResponse(textContent);
        json parsed = check cleanJson.fromJsonString();
        map<json> data = check parsed.ensureType();

        // Extraire les champs
        string? composer = self.extractOptionalString(data, "composer");
        string? period = self.extractOptionalString(data, "period");
        string? musicalForm = self.extractOptionalString(data, "musicalForm");
        string? opusCatalog = self.extractOptionalString(data, "opusCatalog");
        string? workTitle = self.extractOptionalString(data, "workTitle");
        string? movement = self.extractOptionalString(data, "movement");

        // Extraire confidence
        decimal? confidence = ();
        decimal|error conf = data["confidence"].ensureType();
        if conf is decimal {
            confidence = conf;
        } else {
            // Essayer de parser depuis un nombre
            float|error confFloat = data["confidence"].ensureType();
            if confFloat is float {
                confidence = <decimal>confFloat;
            }
        }

        return {
            composer: composer,
            period: period,
            musicalForm: musicalForm,
            opusCatalog: opusCatalog,
            workTitle: workTitle,
            movement: movement,
            confidence: confidence
        };
    }

    # Parse la réponse de Claude pour la vérification is_composer
    #
    # + response - Réponse JSON brute de l'API Claude
    # + return - Résultat de la vérification ou erreur
    private function parseComposerCheckResponse(json response) returns ClaudeComposerCheck|error {
        // Extraire le contenu texte de la réponse
        json[] content = check response.content.ensureType();
        if content.length() == 0 {
            return error("Empty response from Claude");
        }

        map<json> firstContent = check content[0].ensureType();
        string textContent = (check firstContent["text"]).toString();

        // Nettoyer et parser le JSON
        string cleanJson = self.cleanJsonResponse(textContent);
        json parsed = check cleanJson.fromJsonString();
        map<json> data = check parsed.ensureType();

        // Extraire la réponse
        string answer = data["answer"].toString().toUpperAscii();
        boolean isHistoricalComposer = answer == "A";

        string? explanation = self.extractOptionalString(data, "explanation");

        return {
            isHistoricalComposer: isHistoricalComposer,
            explanation: explanation
        };
    }

    # Nettoie une réponse JSON (enlève les backticks markdown)
    #
    # + textContent - Contenu texte brut
    # + return - JSON nettoyé
    private function cleanJsonResponse(string textContent) returns string {
        string cleanJson = textContent;
        if cleanJson.startsWith("```json") {
            cleanJson = cleanJson.substring(7);
        } else if cleanJson.startsWith("```") {
            cleanJson = cleanJson.substring(3);
        }
        if cleanJson.endsWith("```") {
            cleanJson = cleanJson.substring(0, cleanJson.length() - 3);
        }
        return cleanJson.trim();
    }

    # Extrait une chaîne optionnelle d'un map JSON
    #
    # + data - Map de données JSON
    # + key - Clé à extraire
    # + return - Valeur ou nil
    private function extractOptionalString(map<json> data, string key) returns string? {
        if !data.hasKey(key) || data[key] is () {
            return ();
        }
        string value = data[key].toString();
        if value == "null" || value == "" {
            return ();
        }
        return value;
    }
}
