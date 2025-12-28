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

2. Éditer `Config.toml` avec vos clés API :
   ```toml
   apiKey = "votre_cle_api_lastfm"
   servicePort = 8099
   enrichedServicePort = 8098
   claudeApiKey = "votre_cle_api_claude"  # Optionnel, pour l'enrichissement AI
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

### Service Last.fm (port 8099) - Données brutes

| Méthode | Endpoint | Description |
|---------|----------|-------------|
| GET | `/api/lastfm/health` | Health check |
| GET | `/api/lastfm/users/{username}` | Infos utilisateur |
| GET | `/api/lastfm/users/{username}/recent` | Écoutes récentes |
| GET | `/api/lastfm/users/{username}/top/artists` | Top artistes |
| GET | `/api/lastfm/users/{username}/top/albums` | Top albums |
| GET | `/api/lastfm/users/{username}/top/tracks` | Top tracks |

### Service Enrichi (port 8098) - Données enrichies SQLite

| Méthode | Endpoint | Description |
|---------|----------|-------------|
| GET | `/api/enriched/health` | Health check |
| POST | `/api/enriched/users/{username}/sync` | Synchronise et enrichit les données depuis Last.fm |
| GET | `/api/enriched/users/{username}/scrobbles` | Récupère les scrobbles enrichis |
| GET | `/api/enriched/artists` | Liste tous les artistes enrichis |
| GET | `/api/enriched/tracks` | Liste tous les tracks enrichis |

## Paramètres de requête

### `/recent`
- `limit` (int, 1-200, défaut: 50) - Nombre de tracks
- `page` (int, défaut: 1) - Page de résultats

### `/top/*`
- `period` (string, défaut: "overall") - Période d'analyse
  - `7day` | `1month` | `3month` | `6month` | `12month` | `overall`
- `limit` (int, défaut: 10) - Nombre de résultats

### `/sync` (POST)
- `limit` (int, 1-200, défaut: 50) - Nombre de tracks à synchroniser
- `aiLimit` (int, 0-50, défaut: 50) - Nombre max d'appels Claude AI (0 = désactivé)

### `/scrobbles`
- `limit` (int, 1-200, défaut: 50) - Nombre de résultats
- `offset` (int, défaut: 0) - Décalage pour la pagination

## Exemples

### Service Last.fm (données brutes)

```bash
# Health check
curl http://localhost:8099/api/lastfm/health

# Infos utilisateur
curl http://localhost:8099/api/lastfm/users/monuser

# 20 dernières écoutes
curl "http://localhost:8099/api/lastfm/users/monuser/recent?limit=20"

# Top 10 artistes du mois
curl "http://localhost:8099/api/lastfm/users/monuser/top/artists?period=1month&limit=10"

# Top albums de la semaine
curl "http://localhost:8099/api/lastfm/users/monuser/top/albums?period=7day"
```

### Service Enrichi (données enrichies)

```bash
# Health check
curl http://localhost:8098/api/enriched/health

# Synchroniser les données (enrichissement MusicBrainz + Claude AI, max 50 appels AI)
curl -X POST "http://localhost:8098/api/enriched/users/monuser/sync?limit=20"

# Synchroniser avec enrichissement AI limité à 5 artistes
curl -X POST "http://localhost:8098/api/enriched/users/monuser/sync?limit=20&aiLimit=5"

# Synchroniser sans enrichissement AI (MusicBrainz uniquement)
curl -X POST "http://localhost:8098/api/enriched/users/monuser/sync?limit=20&aiLimit=0"

# Récupérer les scrobbles enrichis
curl "http://localhost:8098/api/enriched/users/monuser/scrobbles?limit=10"

# Récupérer les scrobbles avec pagination
curl "http://localhost:8098/api/enriched/users/monuser/scrobbles?limit=10&offset=10"

# Liste des artistes enrichis
curl http://localhost:8098/api/enriched/artists

# Liste des tracks enrichis
curl http://localhost:8098/api/enriched/tracks
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

### Sync Response (POST /sync)
```json
{
  "success": true,
  "message": "Synchronized 20 tracks for user monuser",
  "tracksProcessed": 20,
  "artistsEnrichedByAI": 2,
  "cacheStats": {
    "artists": 45,
    "tracks": 120
  }
}
```

### Enriched Scrobbles
```json
{
  "user": "username",
  "totalScrobbles": 150,
  "scrobbles": [
    {
      "listenedAt": 1703952000,
      "datetime": "2024-12-30 14:00:00",
      "artist": "Johann Sebastian Bach",
      "track": "Goldberg Variations, BWV 988: Aria",
      "album": "Goldberg Variations",
      "loved": true,
      "genres": ["classical", "baroque"],
      "composer": "Johann Sebastian Bach",
      "isClassical": true,
      "qualityScore": 0.95
    }
  ]
}
```

### Enriched Artists
```json
[
  {
    "name": "Johann Sebastian Bach",
    "mbid": "24f1766e-9635-4d58-a4d4-9413f9f98a4c",
    "genres": ["classical", "baroque"],
    "composer": "Johann Sebastian Bach",
    "isComposer": true,
    "qualityScore": 0.95,
    "lastUpdated": "2024-12-28T15:30:00Z",
    "enrichedByAI": true
  }
]
```

## Déploiement Docker

```dockerfile
FROM ballerina/ballerina:2201.10.0

WORKDIR /app
COPY . .

RUN bal build

EXPOSE 8098 8099
CMD ["java", "-jar", "target/bin/lastfm_history.jar"]
```

## Intégration WSO2

Ce service peut être déployé comme microservice standalone ou intégré via WSO2 Micro Integrator en tant que endpoint REST.
