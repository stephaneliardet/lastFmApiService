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
}
