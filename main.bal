import ballerina/io;

const string USERNAME = "sliardet";

public function main() returns error? {
    io:println("");

    // Initialiser le service d'enrichissement
    EnrichmentService enricher = check new ();

    // Infos utilisateur
    SimpleUserInfo user = check lastfmClient.getUserInfo(USERNAME);
    io:println(string `👤 Utilisateur: ${user.name}`);
    io:println(string `   Scrobbles totaux: ${user.totalScrobbles}`);
    io:println(string `   Inscrit depuis: ${user.registeredDate}`);

    // Écoutes récentes
    ScrobblesResponse recent = check lastfmClient.getRecentTracks(USERNAME, 10, 1);

    // Enrichir les tracks avec MusicBrainz
    io:println("");
    io:println("🔍 Enrichissement des métadonnées...");
    EnrichedTrack[] enrichedTracks = check enricher.enrichTracks(recent.tracks);

    // Afficher les tracks enrichis
    displayEnrichedTracks(enrichedTracks, recent);

    // Statistiques du cache
    var stats = enricher.getCacheStats();
    io:println("");
    io:println(string `📊 Cache: ${stats.artists} artistes, ${stats.tracks} tracks`);

    // Artistes nécessitant enrichissement IA
    CachedArtist[] needsAI = enricher.getArtistsNeedingAIEnrichment();
    if needsAI.length() > 0 {
        io:println(string `⚠️  ${needsAI.length()} artistes avec score < 0.8 (candidats pour Claude AI)`);
    }
}

function displayEnrichedTracks(EnrichedTrack[] tracks, ScrobblesResponse data) {
    io:println("");
    io:println("============================================================");
    io:println(string `Historique d'écoute de ${data.user}`);
    io:println(string `Total scrobbles: ${data.totalScrobbles}`);
    io:println(string `Page ${data.page}/${data.totalPages}`);
    io:println("============================================================");
    io:println("");

    foreach EnrichedTrack track in tracks {
        string timestamp = track.nowPlaying ? "🎵 En cours..." : (track.datetime ?: "");
        string loved = track.loved ? "❤️ " : "";

        // Affichage adapté pour la musique classique
        string artistDisplay;
        if track.isClassical && track.composer is string {
            string comp = <string>track.composer;
            artistDisplay = string `${comp} (interpr.: ${track.artist})`;
        } else {
            artistDisplay = track.artist;
        }

        io:println(string `${timestamp} | ${loved}${artistDisplay}`);
        io:println(string `             🎵 ${track.track}`);
        io:println(string `             💿 ${track.album}`);

        // Afficher les genres si disponibles
        if track.genres.length() > 0 {
            io:println(string `             🏷️  ${track.genres.toString()}`);
        }

        // Afficher le score de qualité
        string scoreBar = getScoreBar(track.qualityScore);
        io:println(string `             📊 Score: ${scoreBar} (${track.qualityScore})`);

        io:println("------------------------------------------------------------");
    }
}

function getScoreBar(decimal score) returns string {
    int filled = <int>(score * 10.0d);
    string bar = "";
    foreach int i in 0 ..< 10 {
        bar += i < filled ? "█" : "░";
    }
    return bar;
}

function displayTopArtists(SimpleArtist[] artists, string period) {
    map<string> periodLabels = {
        "7day": "7 derniers jours",
        "1month": "Dernier mois",
        "3month": "3 derniers mois",
        "6month": "6 derniers mois",
        "12month": "Dernière année",
        "overall": "Depuis toujours"
    };

    string label = periodLabels[period] ?: period;

    io:println("");
    io:println("============================================================");
    io:println(string `Top Artistes - ${label}`);
    io:println("============================================================");
    io:println("");

    foreach SimpleArtist artist in artists {
        io:println(string `${artist.rank.toString().padStart(2)}. ${artist.name} (${artist.playcount} écoutes)`);
    }
    io:println("");
}
