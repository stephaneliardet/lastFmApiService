// Types pour l'API Last.fm

# Configuration du client Last.fm
#
# + apiKey - Clé API Last.fm
# + baseUrl - URL de base de l'API Last.fm
public type LastFMConfig record {|
    string apiKey;
    string baseUrl = "https://ws.audioscrobbler.com/2.0/";
|};

# Informations utilisateur
#
# + name - Nom d'utilisateur
# + realname - Nom réel de l'utilisateur
# + country - Pays de l'utilisateur
# + playcount - Nombre total d'écoutes
# + url - URL du profil Last.fm
# + registered - Date d'inscription
public type UserInfo record {|
    string name;
    string realname?;
    string country?;
    int playcount;
    string url;
    string registered;
|};

# Image Last.fm
#
# + \#text - URL de l'image
# + size - Taille de l'image (small, medium, large, etc.)
public type Image record {|
    string \#text;
    string size;
|};

# Artiste
#
# + \#text - Nom de l'artiste (format alternatif)
# + name - Nom de l'artiste
# + mbid - MusicBrainz ID
# + playcount - Nombre d'écoutes
public type Artist record {
    string \#text?;
    string name?;
    string mbid?;
    int playcount?;
};

# Album
#
# + \#text - Nom de l'album (format alternatif)
# + name - Nom de l'album
# + mbid - MusicBrainz ID
# + playcount - Nombre d'écoutes
# + artist - Artiste de l'album
public type Album record {|
    string \#text?;
    string name?;
    string mbid?;
    int playcount?;
    Artist artist?;
|};

# Date d'écoute
#
# + uts - Timestamp Unix
# + \#text - Date formatée
public type TrackDate record {|
    string uts;
    string \#text;
|};

# Attributs now playing
#
# + nowplaying - Indique si le track est en cours de lecture
public type NowPlayingAttr record {|
    string nowplaying?;
|};

# Track écouté
#
# + name - Nom du morceau
# + mbid - MusicBrainz ID
# + artist - Artiste du morceau
# + album - Album du morceau
# + image - Images associées au morceau
# + date - Date d'écoute
# + loved - Indique si le morceau est aimé
# + \@attr - Attributs additionnels (now playing)
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
#
# + user - Nom d'utilisateur
# + page - Page courante
# + perPage - Éléments par page
# + totalPages - Nombre total de pages
# + total - Nombre total d'éléments
public type PaginationAttr record {|
    string user;
    string page;
    string perPage;
    string totalPages;
    string total;
|};

# Réponse recent tracks
#
# + recenttracks - Conteneur des écoutes récentes
public type RecentTracksResponse record {|
    record {|
        ScrobbledTrack[] track;
        PaginationAttr \@attr;
    |} recenttracks;
|};

# Réponse user info
#
# + user - Informations de l'utilisateur
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
#
# + name - Nom de l'artiste
# + mbid - MusicBrainz ID
# + playcount - Nombre d'écoutes
# + url - URL du profil Last.fm
# + image - Images de l'artiste
public type TopArtist record {
    string name;
    string mbid?;
    string playcount;
    string url;
    Image[] image?;
};

# Réponse top artists
#
# + topartists - Conteneur des top artistes
public type TopArtistsResponse record {
    record {
        TopArtist[] artist;
    } topartists;
};

# Top Album
#
# + name - Nom de l'album
# + mbid - MusicBrainz ID
# + playcount - Nombre d'écoutes
# + artist - Artiste de l'album
# + image - Images de l'album
public type TopAlbum record {|
    string name;
    string mbid?;
    string playcount;
    Artist artist;
    Image[] image?;
|};

# Réponse top albums
#
# + topalbums - Conteneur des top albums
public type TopAlbumsResponse record {|
    record {|
        TopAlbum[] album;
    |} topalbums;
|};

# Top Track
#
# + name - Nom du morceau
# + mbid - MusicBrainz ID
# + playcount - Nombre d'écoutes
# + artist - Artiste du morceau
# + image - Images du morceau
public type TopTrack record {|
    string name;
    string mbid?;
    string playcount;
    Artist artist;
    Image[] image?;
|};

# Réponse top tracks
#
# + toptracks - Conteneur des top tracks
public type TopTracksResponse record {|
    record {|
        TopTrack[] track;
    |} toptracks;
|};

// === Types simplifiés pour les réponses REST ===

# Track simplifié pour la réponse API
#
# + timestamp - Timestamp Unix de l'écoute
# + datetime - Date et heure formatées
# + artist - Nom de l'artiste
# + track - Nom du morceau
# + album - Nom de l'album
# + loved - Indique si le track est aimé
# + nowPlaying - Indique si le track est en cours de lecture
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
#
# + user - Nom d'utilisateur
# + page - Page courante
# + totalPages - Nombre total de pages
# + totalScrobbles - Nombre total d'écoutes
# + tracks - Liste des tracks
public type ScrobblesResponse record {|
    string user;
    int page;
    int totalPages;
    int totalScrobbles;
    SimpleTrack[] tracks;
|};

# Artiste simplifié
#
# + rank - Position dans le classement
# + name - Nom de l'artiste
# + playcount - Nombre d'écoutes
public type SimpleArtist record {|
    int rank;
    string name;
    int playcount;
|};

# Album simplifié
#
# + rank - Position dans le classement
# + name - Nom de l'album
# + artist - Nom de l'artiste
# + playcount - Nombre d'écoutes
public type SimpleAlbum record {|
    int rank;
    string name;
    string artist;
    int playcount;
|};

# Track simplifié pour top tracks
#
# + rank - Position dans le classement
# + name - Nom du morceau
# + artist - Nom de l'artiste
# + playcount - Nombre d'écoutes
public type SimpleTopTrack record {|
    int rank;
    string name;
    string artist;
    int playcount;
|};

# Réponse user info simplifiée
#
# + name - Nom d'utilisateur
# + realname - Nom réel de l'utilisateur
# + country - Pays de l'utilisateur
# + totalScrobbles - Nombre total d'écoutes
# + registeredDate - Date d'inscription
# + profileUrl - URL du profil Last.fm
public type SimpleUserInfo record {|
    string name;
    string realname;
    string country;
    int totalScrobbles;
    string registeredDate;
    string profileUrl;
|};
