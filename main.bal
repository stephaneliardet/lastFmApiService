import ballerina/io;

const string USERNAME = "sliardet";

public function main() returns error? {
    io:println("");

    // Infos utilisateur
    SimpleUserInfo user = check lastfmClient.getUserInfo(USERNAME);
    io:println(string `👤 Utilisateur: ${user.name}`);
    io:println(string `   Scrobbles totaux: ${user.totalScrobbles}`);
    io:println(string `   Inscrit depuis: ${user.registeredDate}`);

    // Écoutes récentes
    ScrobblesResponse recent = check lastfmClient.getRecentTracks(USERNAME, 20, 1);
    displayRecentTracks(recent);

    // Top artistes du mois
    SimpleArtist[] topArtists = check lastfmClient.getTopArtists(USERNAME, "1month", 10);
    displayTopArtists(topArtists, "1month");
}

function displayRecentTracks(ScrobblesResponse data) {
    io:println("");
    io:println("============================================================");
    io:println(string `Historique d'écoute de ${data.user}`);
    io:println(string `Total scrobbles: ${data.totalScrobbles}`);
    io:println(string `Page ${data.page}/${data.totalPages}`);
    io:println("============================================================");
    io:println("");

    foreach SimpleTrack track in data.tracks {
        string timestamp = track.nowPlaying ? "🎵 En cours..." : (track.datetime ?: "");
        string loved = track.loved ? "❤️ " : "";

        io:println(string `${timestamp} | ${loved}${track.artist} - ${track.track}`);
        io:println(string `             Album: ${track.album}`);
        io:println("------------------------------------------------------------");
    }
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
