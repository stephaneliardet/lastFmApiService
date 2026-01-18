# Améliorations du pipeline d'extraction Last.fm (Ballerina)

## Contexte

Ce projet Ballerina extrait l'historique d'écoute depuis l'API Last.fm et enrichit les métadonnées via l'API Claude avant stockage dans une base SQLite. L'objectif final est d'alimenter un moteur de recommandation musicale personnel, avec deux pipelines distincts : classique/baroque (centré sur l'œuvre et le compositeur) et autres styles (centré sur l'artiste).

Un audit des données actuelles (795 scrobbles, 85 artistes, 482 tracks) a révélé plusieurs problèmes de qualité à corriger.

---

## Améliorations demandées

### 1. Validation post-enrichissement du champ `composer`

**Problème** : Le LLM retourne parfois le nom d'album au lieu du compositeur.

Exemple observé :
```
artist: "Ethiopiques" | track: "Temeles" | composer: "Best of Ethiopiques" ❌
```

**Solution** : Après l'appel LLM, valider le champ `composer` retourné. Si la valeur :
- contient des mots-clés typiques d'album : "Best of", "Complete", "Collection", "Greatest Hits", "Live at", "Anthology", "Edition"
- OU correspond exactement ou partiellement au champ `album_name`
- OU est vide ou "Unknown"

Alors : ne PAS enregistrer le compositeur (laisser NULL). Ne pas faire de reprompt, simplement ignorer la valeur invalide.

---

### 2. Amélioration du prompt LLM pour la musique classique/baroque

**Problème** : Des tracks clairement classiques n'ont pas de compositeur détecté.

Exemples observés :
```
Il Giardino Armonico | "Sinfonia op.XII N°4 in D minor" | composer: NULL ❌
Magdalena Kožená     | "Con che soavità, SV 139"        | composer: NULL ❌
```

**Solution** : Adapter le prompt d'enrichissement selon le contexte :

1. Détecter si l'artiste/track est dans un contexte classique (genres contiennent : "baroque", "classical", "early music", "romantic", "opera", "chamber music", "orchestral")

2. Pour ces cas, utiliser un prompt enrichi qui :
   - Précise que l'artiste est un interprète/ensemble, pas le compositeur
   - Demande d'identifier le compositeur historique original
   - Exploite les indices dans le titre : numéros de catalogue (BWV, HWV, K., Op., SV, Wq., etc.), tonalités, formes musicales

Exemple de prompt enrichi pour le contexte classique :
```
L'artiste "{artist_name}" est un interprète ou ensemble de musique classique/baroque.
Le morceau "{track_name}" de l'album "{album_name}" est probablement une œuvre d'un compositeur historique.

Identifie :
1. Le compositeur original de cette œuvre (pas l'interprète)
2. La période musicale : baroque, classical, romantic, modern, contemporary
3. La forme musicale : symphony, concerto, sonata, cantata, opera, oratorio, quartet, trio, suite, mass, motet, aria, lied, étude, prelude, fugue, other
4. Le numéro de catalogue si présent (BWV, HWV, K., Op., Wq., SV, etc.)
5. Le titre normalisé de l'œuvre (sans le mouvement)
6. Le mouvement si applicable

Indices à exploiter :
- "SV" = catalogue Monteverdi
- "BWV" = catalogue Bach
- "HWV" = catalogue Handel
- "K." ou "KV" = catalogue Mozart
- "Wq." = catalogue C.P.E. Bach
- "Op." = numéro d'opus générique

Réponds en JSON.
```

---

### 3. Refonte de la logique `is_composer`

**Problème** : Faux positifs (interprètes marqués compositeurs) et faux négatifs (vrais compositeurs non marqués).

Observé :
```
is_composer = 1 : Émilie Simon, Derek Han ❌ (ce sont des interprètes)
is_composer = 0 : Johann Sebastian Bach ❌ (c'est un compositeur!)
```

**Solution** : Réviser la logique de détection en deux temps :

1. **Pré-filtrage par genres** : Si les genres contiennent "baroque", "classical", "romantic", "renaissance", "medieval" → candidat potentiel compositeur historique

2. **Question LLM explicite et binaire** :
```
"{artist_name}" est-il :
A) Un compositeur historique dont les œuvres sont interprétées par d'autres (ex: Bach, Mozart, Vivaldi, Monteverdi)
B) Un interprète, ensemble, orchestre ou artiste contemporain qui performe ses propres créations ou celles d'autres

Critères :
- Un compositeur historique est généralement décédé et ses œuvres sont au répertoire classique
- Un ensemble baroque (ex: "Il Giardino Armonico") n'est PAS un compositeur même s'il joue du baroque
- Un artiste contemporain qui compose sa propre musique (ex: "Émilie Simon") n'est PAS un "compositeur" au sens classique

Réponds uniquement : A ou B
```

Marquer `is_composer = 1` uniquement si réponse = A.

---

### 4. Normalisation des artistes (canonical_artist_id)

**Problème** : Le même artiste apparaît sous plusieurs variantes, fragmentant les statistiques.

Observé :
```
"Rachel Podger"                                    → 39 scrobbles
"Rachel Podger, Brecon Baroque"                    → 50 scrobbles
"Holland Baroque Society / Rachel Podger (violin)" → 44 scrobbles
"Brecon Baroque, Rachel Podger"                    → ?
```

**Solution** :

1. **Modifier le schéma** - Ajouter une colonne à la table `artists` :
```sql
ALTER TABLE artists ADD COLUMN canonical_artist_id INTEGER REFERENCES artists(id);
```

2. **Logique d'extraction de l'artiste principal** :
   - Parser le champ `artist_name` pour identifier les séparateurs : `, ` (virgule), ` / ` (slash), ` & ` (ampersand), ` ; ` (point-virgule), ` and ` (and)
   - Extraire le premier segment comme candidat artiste principal
   - Pour les cas ambigus (ex: "Holland Baroque Society / Rachel Podger"), utiliser le LLM :

```
Dans cette attribution d'artiste : "{artist_name}"
Qui est l'artiste ou ensemble PRINCIPAL (celui qui serait crédité en premier sur une pochette) ?
Réponds uniquement avec le nom exact tel qu'il devrait apparaître.
```

3. **Lier à l'entité canonique** :
   - Chercher si l'artiste principal existe déjà dans la table `artists`
   - Si oui, mettre `canonical_artist_id` = id de l'artiste existant
   - Si non, l'artiste est sa propre référence canonique (`canonical_artist_id` = son propre `id` ou NULL)

4. **Gestion des accents** (voir point 6) pour améliorer la correspondance.

---

### 5. Ajout des colonnes d'enrichissement pour le scoring

**Problème** : Le schéma actuel ne permet pas le scoring multi-critères prévu (période, forme musicale, œuvre).

**Solution** : Enrichir la table `tracks` avec de nouvelles colonnes :

```sql
ALTER TABLE tracks ADD COLUMN period TEXT;           -- baroque, classical, romantic, modern, contemporary
ALTER TABLE tracks ADD COLUMN musical_form TEXT;     -- symphony, concerto, sonata, cantata, opera, quartet, trio, suite, aria, lied, other
ALTER TABLE tracks ADD COLUMN opus_catalog TEXT;     -- BWV 1001, HWV 34, K. 466, Op. 12/4, Wq. 183/1, SV 139
ALTER TABLE tracks ADD COLUMN work_title TEXT;       -- Titre normalisé de l'œuvre complète (pas du mouvement)
ALTER TABLE tracks ADD COLUMN movement TEXT;         -- I. Allegro, II. Andante, III. Presto, etc.
```

Ces champs doivent être remplis par le prompt d'enrichissement classique (voir point 2).

**Valeurs attendues pour `period`** :
- `renaissance` (avant 1600)
- `baroque` (1600-1750)
- `classical` (1750-1820)
- `romantic` (1820-1900)
- `modern` (1900-1945)
- `contemporary` (après 1945)
- `null` pour la musique non-classique

**Valeurs attendues pour `musical_form`** :
- symphony, concerto, sonata, quartet, trio, quintet, suite, partita
- cantata, oratorio, opera, mass, motet, magnificat, passion
- aria, lied, chanson, madrigal
- prelude, fugue, toccata, fantasia, étude, variations
- sinfonia, overture, divertimento, serenade
- other (si non identifiable)
- null pour la musique non-classique

---

### 6. Normalisation des accents pour la déduplication

**Problème** : Doublons créés par les variantes d'encodage.

Observé :
```
"Magdalena Kozená"  (sans háček)
"Magdalena Kožená"  (avec háček)
```

**Solution** : Ajouter un champ de normalisation pour faciliter la recherche de doublons :

```sql
ALTER TABLE artists ADD COLUMN name_normalized TEXT;
```

**Logique de normalisation** :
1. Convertir en minuscules
2. Supprimer les accents (NFD + suppression des combining characters)
3. Supprimer la ponctuation
4. Normaliser les espaces multiples

Exemple en pseudo-code :
```
"Magdalena Kožená" → "magdalena kozena"
"Il Giardino Armonico, Giovanni Antonini" → "il giardino armonico giovanni antonini"
```

Utiliser `name_normalized` pour détecter les doublons potentiels avant insertion et pour la recherche de `canonical_artist_id`.

---

## Structure de réponse JSON attendue du LLM (enrichissement classique)

Pour les tracks détectées comme classiques, le prompt doit demander une réponse JSON structurée :

```json
{
  "composer": "Claudio Monteverdi",
  "period": "baroque",
  "musical_form": "madrigal",
  "opus_catalog": "SV 139",
  "work_title": "Con che soavità",
  "movement": null,
  "confidence": 0.95
}
```

Pour les tracks non-classiques, retourner :
```json
{
  "composer": null,
  "period": null,
  "musical_form": null,
  "opus_catalog": null,
  "work_title": null,
  "movement": null,
  "confidence": null
}
```

---

## Ordre d'implémentation suggéré

1. **Schéma SQL** : Ajouter toutes les nouvelles colonnes (migrations)
2. **Normalisation accents** : Implémenter la fonction + remplir `name_normalized`
3. **Validation composer** : Ajouter la validation post-LLM (point 1)
4. **Refonte is_composer** : Nouvelle logique de détection (point 3)
5. **Prompt classique enrichi** : Nouveau prompt + parsing JSON (point 2)
6. **Canonical artist** : Logique de déduplication (point 4)
7. **Ré-enrichissement** : Relancer l'enrichissement sur les données existantes avec les nouvelles règles

---

## Notes techniques

- Le projet utilise WSO2 Ballerina
- Base de données : SQLite
- API d'enrichissement : Claude (Anthropic)
- Les résultats d'enrichissement doivent être mis en cache pour éviter les appels redondants
- Conserver le flag `enriched_by_ai` et ajouter un `enrichment_version` pour tracer les ré-enrichissements