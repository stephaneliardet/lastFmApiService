import ballerina/http;
import ballerina/log;
import ballerina/time;

# Client pour l'API Last.fm
public isolated class LastFMClient {
    
    private final http:Client httpClient;
    private final string apiKey;

    public function init(LastFMConfig config) returns error? {
        self.apiKey = config.apiKey;
        self.httpClient = check new (config.baseUrl);
    }

    # Effectue une requête à l'API Last.fm
    #
    # + method - Méthode API (ex: user.getRecentTracks)
    # + params - Paramètres additionnels
    # + return - Réponse JSON ou erreur
    private function request(string method, map<string> params = {}) returns json|error {
        string queryParams = string `?method=${method}&api_key=${self.apiKey}&format=json`;
        
        foreach var [key, value] in params.entries() {
            queryParams += string `&${key}=${value}`;
        }

        log:printDebug(string `Last.fm API call: ${method}`);
        
        json response = check self.httpClient->get(queryParams);
        
        // Vérifier les erreurs API
        map<json>|error responseMap = response.ensureType();
        if responseMap is map<json> && responseMap.hasKey("error") {
            string message = (check responseMap["message"]).toString();
            return error(string `Last.fm API error: ${message}`);
        }
        
        return response;
    }

    # Récupère les informations d'un utilisateur
    #
    # + username - Nom d'utilisateur Last.fm
    # + return - Infos utilisateur ou erreur
    public function getUserInfo(string username) returns SimpleUserInfo|error {
        json response = check self.request("user.getInfo", {"user": username});
        UserInfoResponse parsed = check response.cloneWithType();
        
        int|string regText = parsed.user.registered.\#text;
        int timestamp = regText is int ? regText : check int:fromString(regText);

        // Convertir le timestamp Unix en date lisible (locale du système)
        time:Utc utcTime = [timestamp, 0];
        time:Civil civilTime = time:utcToCivil(utcTime);
        string registeredDate = string `${civilTime.day}/${civilTime.month}/${civilTime.year}`;

        return {
            name: parsed.user.name,
            realname: parsed.user.realname ?: "",
            country: parsed.user.country ?: "",
            totalScrobbles: check int:fromString(parsed.user.playcount),
            registeredDate: registeredDate,
            profileUrl: parsed.user.url
        };
    }

    # Récupère les écoutes récentes
    #
    # + username - Nom d'utilisateur
    # + 'limit - Nombre de tracks (max 200)
    # + page - Numéro de page
    # + return - Liste des scrobbles ou erreur
    public function getRecentTracks(string username, int 'limit = 50, int page = 1) 
            returns ScrobblesResponse|error {
        
        map<string> params = {
            "user": username,
            "limit": 'limit.toString(),
            "page": page.toString(),
            "extended": "1"
        };

        json response = check self.request("user.getRecentTracks", params);
        RecentTracksResponse parsed = check response.cloneWithType();

        SimpleTrack[] tracks = [];
        foreach ScrobbledTrack t in parsed.recenttracks.track {
            boolean isNowPlaying = t.\@attr?.nowplaying == "true";
            
            tracks.push({
                timestamp: isNowPlaying ? () : t.date?.uts,
                datetime: isNowPlaying ? () : t.date?.\#text,
                artist: t.artist.\#text ?: t.artist.name ?: "Unknown",
                track: t.name,
                album: t.album?.\#text ?: t.album?.name ?: "",
                loved: t.loved == "1",
                nowPlaying: isNowPlaying
            });
        }

        PaginationAttr attr = parsed.recenttracks.\@attr;
        return {
            user: attr.user,
            page: check int:fromString(attr.page),
            totalPages: check int:fromString(attr.totalPages),
            totalScrobbles: check int:fromString(attr.total),
            tracks: tracks
        };
    }

    # Récupère les artistes les plus écoutés
    #
    # + username - Nom d'utilisateur
    # + period - Période: overall|7day|1month|3month|6month|12month
    # + 'limit - Nombre de résultats
    # + return - Liste des top artistes ou erreur
    public function getTopArtists(string username, string period = "overall", int 'limit = 10) 
            returns SimpleArtist[]|error {
        
        map<string> params = {
            "user": username,
            "period": period,
            "limit": 'limit.toString()
        };

        json response = check self.request("user.getTopArtists", params);
        TopArtistsResponse parsed = check response.cloneWithType();

        SimpleArtist[] artists = [];
        int rank = 1;
        foreach TopArtist a in parsed.topartists.artist {
            artists.push({
                rank: rank,
                name: a.name,
                playcount: check int:fromString(a.playcount)
            });
            rank += 1;
        }

        return artists;
    }

    # Récupère les albums les plus écoutés
    #
    # + username - Nom d'utilisateur
    # + period - Période: overall|7day|1month|3month|6month|12month
    # + 'limit - Nombre de résultats
    # + return - Liste des top albums ou erreur
    public function getTopAlbums(string username, string period = "overall", int 'limit = 10) 
            returns SimpleAlbum[]|error {
        
        map<string> params = {
            "user": username,
            "period": period,
            "limit": 'limit.toString()
        };

        json response = check self.request("user.getTopAlbums", params);
        TopAlbumsResponse parsed = check response.cloneWithType();

        SimpleAlbum[] albums = [];
        int rank = 1;
        foreach TopAlbum a in parsed.topalbums.album {
            albums.push({
                rank: rank,
                name: a.name,
                artist: a.artist.\#text ?: a.artist.name ?: "Unknown",
                playcount: check int:fromString(a.playcount)
            });
            rank += 1;
        }

        return albums;
    }

    # Récupère les tracks les plus écoutés
    #
    # + username - Nom d'utilisateur
    # + period - Période: overall|7day|1month|3month|6month|12month
    # + 'limit - Nombre de résultats
    # + return - Liste des top tracks ou erreur
    public function getTopTracks(string username, string period = "overall", int 'limit = 10) 
            returns SimpleTopTrack[]|error {
        
        map<string> params = {
            "user": username,
            "period": period,
            "limit": 'limit.toString()
        };

        json response = check self.request("user.getTopTracks", params);
        TopTracksResponse parsed = check response.cloneWithType();

        SimpleTopTrack[] tracks = [];
        int rank = 1;
        foreach TopTrack t in parsed.toptracks.track {
            tracks.push({
                rank: rank,
                name: t.name,
                artist: t.artist.\#text ?: t.artist.name ?: "Unknown",
                playcount: check int:fromString(t.playcount)
            });
            rank += 1;
        }

        return tracks;
    }
}
