// Utilitaires pour la manipulation de chaînes de caractères

import ballerina/lang.regexp;

# Table de correspondance pour la normalisation des accents (Unicode → ASCII)
# Couvre les caractères latins accentués les plus courants
final readonly & map<string> ACCENT_MAP = {
    // Voyelles avec accents
    "à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "ā": "a", "ă": "a", "ą": "a",
    "À": "a", "Á": "a", "Â": "a", "Ã": "a", "Ä": "a", "Å": "a", "Ā": "a", "Ă": "a", "Ą": "a",
    "è": "e", "é": "e", "ê": "e", "ë": "e", "ē": "e", "ė": "e", "ę": "e",
    "È": "e", "É": "e", "Ê": "e", "Ë": "e", "Ē": "e", "Ė": "e", "Ę": "e",
    "ì": "i", "í": "i", "î": "i", "ï": "i", "ī": "i", "į": "i", "ı": "i",
    "Ì": "i", "Í": "i", "Î": "i", "Ï": "i", "Ī": "i", "Į": "i", "İ": "i",
    "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ø": "o", "ō": "o", "ő": "o",
    "Ò": "o", "Ó": "o", "Ô": "o", "Õ": "o", "Ö": "o", "Ø": "o", "Ō": "o", "Ő": "o",
    "ù": "u", "ú": "u", "û": "u", "ü": "u", "ū": "u", "ů": "u", "ű": "u", "ų": "u",
    "Ù": "u", "Ú": "u", "Û": "u", "Ü": "u", "Ū": "u", "Ů": "u", "Ű": "u", "Ų": "u",
    "ý": "y", "ÿ": "y", "Ý": "y", "Ÿ": "y",
    // Consonnes spéciales
    "ç": "c", "Ç": "c", "ć": "c", "č": "c", "Ć": "c", "Č": "c",
    "ñ": "n", "Ñ": "n", "ń": "n", "ň": "n", "Ń": "n", "Ň": "n",
    "ß": "ss",
    "š": "s", "ś": "s", "Š": "s", "Ś": "s",
    "ž": "z", "ź": "z", "ż": "z", "Ž": "z", "Ź": "z", "Ż": "z",
    "ř": "r", "Ř": "r",
    "ď": "d", "Ď": "d",
    "ť": "t", "Ť": "t",
    "ľ": "l", "ł": "l", "Ľ": "l", "Ł": "l",
    // Ligatures
    "æ": "ae", "Æ": "ae",
    "œ": "oe", "Œ": "oe",
    // Caractères tchèques/slovaques (háčeks)
    "ě": "e", "Ě": "e"
};

# Mots-clés typiques d'album qui ne doivent pas être acceptés comme compositeur
final readonly & string[] INVALID_COMPOSER_KEYWORDS = [
    "best of",
    "complete",
    "collection",
    "greatest hits",
    "live at",
    "live in",
    "anthology",
    "edition",
    "remastered",
    "deluxe",
    "anniversary",
    "vol.",
    "volume",
    "compilation",
    "selected",
    "essential",
    "ultimate",
    "definitive",
    "gold",
    "platinum",
    "box set",
    "recordings"
];

# Normalise une chaîne de caractères pour la comparaison/déduplication
# - Convertit en minuscules
# - Supprime les accents
# - Supprime la ponctuation
# - Normalise les espaces multiples
#
# + input - Chaîne à normaliser
# + return - Chaîne normalisée
public isolated function normalizeString(string input) returns string {
    string result = input;

    // 1. Convertir en minuscules
    result = result.toLowerAscii();

    // 2. Remplacer les caractères accentués
    foreach [string, string] [accented, normalized] in ACCENT_MAP.entries() {
        result = regexp:replace(re `${accented}`, result, normalized);
    }

    // 3. Supprimer la ponctuation (garder uniquement lettres, chiffres et espaces)
    result = regexp:replaceAll(re `[^\p{L}\p{N}\s]`, result, "");

    // 4. Normaliser les espaces multiples en un seul espace
    result = regexp:replaceAll(re `\s+`, result, " ");

    // 5. Supprimer les espaces en début et fin
    result = result.trim();

    return result;
}

# Valide si une valeur de compositeur est acceptable
# Rejette les valeurs qui ressemblent à des noms d'album
#
# + composerValue - Valeur du compositeur à valider
# + albumName - Nom de l'album (optionnel) pour comparaison
# + return - true si valide, false si invalide
public isolated function isValidComposer(string? composerValue, string? albumName = ()) returns boolean {
    if composerValue is () || composerValue.trim() == "" {
        return false;
    }

    string composerLower = composerValue.toLowerAscii();

    // Vérifier les mots-clés d'album
    foreach string keyword in INVALID_COMPOSER_KEYWORDS {
        if composerLower.includes(keyword) {
            return false;
        }
    }

    // Vérifier "Unknown" ou similaire
    if composerLower == "unknown" || composerLower == "n/a" || composerLower == "null" {
        return false;
    }

    // Comparer avec le nom d'album si fourni
    if albumName is string && albumName.trim() != "" {
        string albumNormalized = normalizeString(albumName);
        string composerNormalized = normalizeString(composerValue);

        // Si le compositeur correspond exactement ou partiellement à l'album
        if albumNormalized == composerNormalized {
            return false;
        }

        // Si l'album contient le "compositeur" ou vice versa (substring significatif)
        if albumNormalized.includes(composerNormalized) && composerNormalized.length() > 3 {
            return false;
        }
    }

    return true;
}

# Extrait l'artiste principal d'un nom d'artiste composite
# Ex: "Rachel Podger, Brecon Baroque" → "Rachel Podger"
# Ex: "Holland Baroque Society / Rachel Podger" → "Holland Baroque Society"
#
# + artistName - Nom complet de l'artiste (peut contenir plusieurs artistes)
# + return - Nom de l'artiste principal (premier segment)
public isolated function extractMainArtist(string artistName) returns string {
    string result = artistName.trim();

    // Liste des séparateurs courants (ordre de priorité)
    string[] separators = [" / ", ", ", " & ", " ; ", " and ", " feat. ", " feat ", " ft. ", " ft "];

    foreach string separator in separators {
        if result.includes(separator) {
            int? idx = result.indexOf(separator);
            if idx is int && idx > 0 {
                result = result.substring(0, idx).trim();
                break;
            }
        }
    }

    return result;
}

# Détecte si un artiste est dans un contexte classique basé sur ses genres
#
# + genres - Liste des genres de l'artiste
# + return - true si classique, false sinon
public isolated function isClassicalContext(string[] genres) returns boolean {
    string[] classicalGenres = [
        "baroque",
        "classical",
        "early music",
        "romantic",
        "opera",
        "chamber music",
        "orchestral",
        "renaissance",
        "medieval",
        "contemporary classical",
        "modern classical",
        "choral",
        "sacred",
        "cantata",
        "symphony",
        "concerto"
    ];

    foreach string genre in genres {
        string genreLower = genre.toLowerAscii();
        foreach string classicalGenre in classicalGenres {
            if genreLower.includes(classicalGenre) {
                return true;
            }
        }
    }

    return false;
}
