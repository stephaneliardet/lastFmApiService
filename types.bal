// Types pour l'API Last.fm

# Configuration du client Last.fm
public type LastFMConfig record {|
    string apiKey;
    string baseUrl = "https://ws.audioscrobbler.com/2.0/";
|};

# Informations utilisateur
public type UserInfo record {|
    string name;
    string realname?;
    string country?;
    int playcount;
    string url;
    string registered;
|};

# Image Last.fm
public type Image record {|
    string \#text;
    string size;
|};

# Artiste
public type Artist record {
    string \#text?;
    string name?;
    string mbid?;
    int playcount?;
};

# Album
public type Album record {|
    string \#text?;
    string name?;
    string mbid?;
    int playcount?;
    Artist artist?;
|};

# Date d'écoute
public type TrackDate record {|
    string uts;
    string \#text;
|};

# Attributs now playing
public type NowPlayingAttr record {|
    string nowplaying?;
|};

# Track écouté
public type ScrobbledTrack record {
    string name;
    string mbid?;
    Artist artist;
    Album album?;
    Image[] image?;
    TrackDate date?;
    string loved?;
    NowPlayingAttr \@attr?;
};

# Attributs de pagination
public type PaginationAttr record {|
    string user;
    string page;
    string perPage;
    string totalPages;
    string total;
|};

# Réponse recent tracks
public type RecentTracksResponse record {|
    record {|
        ScrobbledTrack[] track;
        PaginationAttr \@attr;
    |} recenttracks;
|};

# Réponse user info
public type UserInfoResponse record {
    record {
        string name;
        string realname?;
        string country?;
        string playcount;
        string url;
        record {int|string \#text;} registered;
    } user;
};

# Top Artist
public type TopArtist record {
    string name;
    string mbid?;
    string playcount;
    string url;
    Image[] image?;
};

# Réponse top artists
public type TopArtistsResponse record {
    record {
        TopArtist[] artist;
    } topartists;
};

# Top Album
public type TopAlbum record {|
    string name;
    string mbid?;
    string playcount;
    Artist artist;
    Image[] image?;
|};

# Réponse top albums
public type TopAlbumsResponse record {|
    record {|
        TopAlbum[] album;
    |} topalbums;
|};

# Top Track
public type TopTrack record {|
    string name;
    string mbid?;
    string playcount;
    Artist artist;
    Image[] image?;
|};

# Réponse top tracks
public type TopTracksResponse record {|
    record {|
        TopTrack[] track;
    |} toptracks;
|};

// === Types simplifiés pour les réponses REST ===

# Track simplifié pour la réponse API
public type SimpleTrack record {|
    string timestamp?;
    string datetime?;
    string artist;
    string track;
    string album;
    boolean loved;
    boolean nowPlaying;
|};

# Réponse paginée des écoutes
public type ScrobblesResponse record {|
    string user;
    int page;
    int totalPages;
    int totalScrobbles;
    SimpleTrack[] tracks;
|};

# Artiste simplifié
public type SimpleArtist record {|
    int rank;
    string name;
    int playcount;
|};

# Album simplifié  
public type SimpleAlbum record {|
    int rank;
    string name;
    string artist;
    int playcount;
|};

# Track simplifié pour top tracks
public type SimpleTopTrack record {|
    int rank;
    string name;
    string artist;
    int playcount;
|};

# Réponse user info simplifiée
public type SimpleUserInfo record {|
    string name;
    string realname;
    string country;
    int totalScrobbles;
    string registeredDate;
    string profileUrl;
|};
