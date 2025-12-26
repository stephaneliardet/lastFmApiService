# Last.fm History Service (Ballerina)

Service REST Ballerina pour accéder à l'historique d'écoute Last.fm.

## Prérequis

- Ballerina Swan Lake 2201.10.0+
- Clé API Last.fm : https://www.last.fm/api/account/create

## Configuration

1. Copier le fichier de configuration :
   ```bash
   cp Config.toml.example Config.toml
   ```

2. Éditer `Config.toml` avec votre clé API :
   ```toml
   apiKey = "votre_cle_api"
   servicePort = 8080
   ```

## Lancement

```bash
# Mode développement
bal run

# Build et run
bal build
java -jar target/bin/lastfm_history.jar
```

## Endpoints REST

| Méthode | Endpoint | Description |
|---------|----------|-------------|
| GET | `/api/lastfm/health` | Health check |
| GET | `/api/lastfm/users/{username}` | Infos utilisateur |
| GET | `/api/lastfm/users/{username}/recent` | Écoutes récentes |
| GET | `/api/lastfm/users/{username}/top/artists` | Top artistes |
| GET | `/api/lastfm/users/{username}/top/albums` | Top albums |
| GET | `/api/lastfm/users/{username}/top/tracks` | Top tracks |

## Paramètres de requête

### `/recent`
- `limit` (int, 1-200, défaut: 50) - Nombre de tracks
- `page` (int, défaut: 1) - Page de résultats

### `/top/*`
- `period` (string, défaut: "overall") - Période d'analyse
  - `7day` | `1month` | `3month` | `6month` | `12month` | `overall`
- `limit` (int, défaut: 10) - Nombre de résultats

## Exemples

```bash
# Health check
curl http://localhost:8080/api/lastfm/health

# Infos utilisateur
curl http://localhost:8080/api/lastfm/users/monuser

# 20 dernières écoutes
curl "http://localhost:8080/api/lastfm/users/monuser/recent?limit=20"

# Top 10 artistes du mois
curl "http://localhost:8080/api/lastfm/users/monuser/top/artists?period=1month&limit=10"

# Top albums de la semaine
curl "http://localhost:8080/api/lastfm/users/monuser/top/albums?period=7day"
```

## Réponses

### User Info
```json
{
  "name": "username",
  "realname": "John Doe",
  "country": "Switzerland",
  "totalScrobbles": 12345,
  "registeredDate": "2020-01-15 10:30",
  "profileUrl": "https://www.last.fm/user/username"
}
```

### Recent Tracks
```json
{
  "user": "username",
  "page": 1,
  "totalPages": 50,
  "totalScrobbles": 2500,
  "tracks": [
    {
      "timestamp": "1703952000",
      "datetime": "30 Dec 2024, 14:00",
      "artist": "Johann Sebastian Bach",
      "track": "Goldberg Variations, BWV 988: Aria",
      "album": "Goldberg Variations",
      "loved": true,
      "nowPlaying": false
    }
  ]
}
```

### Top Artists
```json
[
  {"rank": 1, "name": "Johann Sebastian Bach", "playcount": 234},
  {"rank": 2, "name": "Wolfgang Amadeus Mozart", "playcount": 189}
]
```

## Déploiement Docker

```dockerfile
FROM ballerina/ballerina:2201.10.0

WORKDIR /app
COPY . .

RUN bal build

EXPOSE 8080
CMD ["java", "-jar", "target/bin/lastfm_history.jar"]
```

## Intégration WSO2

Ce service peut être déployé comme microservice standalone ou intégré via WSO2 Micro Integrator en tant que endpoint REST.
