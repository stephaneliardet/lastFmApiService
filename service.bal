import ballerina/http;
import ballerina/log;

# Configuration chargée depuis Config.toml
configurable string apiKey = ?;
configurable int servicePort = 8080;

# Client Last.fm global
final LastFMClient lastfmClient = check new ({apiKey: apiKey});

# Service REST Last.fm History
@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "OPTIONS"]
    }
}
service /api/lastfm on new http:Listener(servicePort) {

    function init() {
        log:printInfo(string `Last.fm service started on port ${servicePort}`);
    }

    # Health check
    # 
    # + return - Status du service
    resource function get health() returns json {
        return {status: "UP", 'service: "lastfm-history"};
    }

    # Informations utilisateur
    #
    # + username - Nom d'utilisateur Last.fm
    # + return - Infos utilisateur ou erreur
    resource function get users/[string username]() returns SimpleUserInfo|http:NotFound|http:InternalServerError {
        SimpleUserInfo|error result = lastfmClient.getUserInfo(username);
        
        if result is error {
            log:printError("Error fetching user info", 'error = result);
            if result.message().includes("User not found") {
                return <http:NotFound>{body: {message: string `User '${username}' not found`}};
            }
            return <http:InternalServerError>{body: {message: result.message()}};
        }
        
        return result;
    }

    # Écoutes récentes
    #
    # + username - Nom d'utilisateur Last.fm
    # + 'limit - Nombre de tracks (1-200, défaut: 50)
    # + page - Numéro de page (défaut: 1)
    # + return - Liste des scrobbles ou erreur
    resource function get users/[string username]/recent(
            int 'limit = 50, 
            int page = 1
    ) returns ScrobblesResponse|http:BadRequest|http:InternalServerError {
        
        // Validation
        if 'limit < 1 || 'limit > 200 {
            return <http:BadRequest>{body: {message: "limit must be between 1 and 200"}};
        }
        if page < 1 {
            return <http:BadRequest>{body: {message: "page must be >= 1"}};
        }

        ScrobblesResponse|error result = lastfmClient.getRecentTracks(username, 'limit, page);
        
        if result is error {
            log:printError("Error fetching recent tracks", 'error = result);
            return <http:InternalServerError>{body: {message: result.message()}};
        }
        
        return result;
    }

    # Top artistes
    #
    # + username - Nom d'utilisateur Last.fm
    # + period - Période: overall|7day|1month|3month|6month|12month
    # + 'limit - Nombre de résultats (défaut: 10)
    # + return - Liste des top artistes ou erreur
    resource function get users/[string username]/top/artists(
            string period = "overall",
            int 'limit = 10
    ) returns SimpleArtist[]|http:BadRequest|http:InternalServerError {
        
        // Validation période
        string[] validPeriods = ["overall", "7day", "1month", "3month", "6month", "12month"];
        if validPeriods.indexOf(period) is () {
            return <http:BadRequest>{
                body: {message: string `Invalid period. Must be one of: ${validPeriods.toString()}`}
            };
        }

        SimpleArtist[]|error result = lastfmClient.getTopArtists(username, period, 'limit);
        
        if result is error {
            log:printError("Error fetching top artists", 'error = result);
            return <http:InternalServerError>{body: {message: result.message()}};
        }
        
        return result;
    }

    # Top albums
    #
    # + username - Nom d'utilisateur Last.fm
    # + period - Période: overall|7day|1month|3month|6month|12month
    # + 'limit - Nombre de résultats (défaut: 10)
    # + return - Liste des top albums ou erreur
    resource function get users/[string username]/top/albums(
            string period = "overall",
            int 'limit = 10
    ) returns SimpleAlbum[]|http:BadRequest|http:InternalServerError {
        
        string[] validPeriods = ["overall", "7day", "1month", "3month", "6month", "12month"];
        if validPeriods.indexOf(period) is () {
            return <http:BadRequest>{
                body: {message: string `Invalid period. Must be one of: ${validPeriods.toString()}`}
            };
        }

        SimpleAlbum[]|error result = lastfmClient.getTopAlbums(username, period, 'limit);
        
        if result is error {
            log:printError("Error fetching top albums", 'error = result);
            return <http:InternalServerError>{body: {message: result.message()}};
        }
        
        return result;
    }

    # Top tracks
    #
    # + username - Nom d'utilisateur Last.fm
    # + period - Période: overall|7day|1month|3month|6month|12month
    # + 'limit - Nombre de résultats (défaut: 10)
    # + return - Liste des top tracks ou erreur
    resource function get users/[string username]/top/tracks(
            string period = "overall",
            int 'limit = 10
    ) returns SimpleTopTrack[]|http:BadRequest|http:InternalServerError {
        
        string[] validPeriods = ["overall", "7day", "1month", "3month", "6month", "12month"];
        if validPeriods.indexOf(period) is () {
            return <http:BadRequest>{
                body: {message: string `Invalid period. Must be one of: ${validPeriods.toString()}`}
            };
        }

        SimpleTopTrack[]|error result = lastfmClient.getTopTracks(username, period, 'limit);
        
        if result is error {
            log:printError("Error fetching top tracks", 'error = result);
            return <http:InternalServerError>{body: {message: result.message()}};
        }
        
        return result;
    }
}
