### contexte:

Nous souhaitons produire une application de proposition d'album basée sur les écoutes précédente. L'argorythme devra faire des propositions d'écoute basée sur les habitudes d'écoute des jours,semaines,mois précédents.

### détails:
l'application récupère les habitudes d'écoute sur le service lastfm au moyen de l'api mise à disposition par le service, documentation disponible à cette adresse: https://www.last.fm/api/

l'algorythm utilise le workflow suivant:

1. appel de l'api lastfm pour récupérer l'historique d'écoute
2. pour chacune des écoutes, le prg tente de déterminer le type de musique auquel apprtient le morceaux (rock, électro, calssique, etc...)
3. l'identification du 2. se fera généralement par le nom de l'artiste au moyen d'appel à différents services API online tels que:
    3.1 musicbrainz le type sera déterminé par un appel à l'API de musicbrainz via la mbid fourni par lastfm
    3.2 claude AI dans le cas où les informations récoltée sont insuffisantes, un appel à l'API Claude AI pourra être effectué pour obtenir des informations ou consolider des informations incomplètes précédemment obtenues.
4. pour chacunes des écoutes le prg tente de trouver le compositeur. Généralement, cette information n'est pas délivrée par l'api lastfm. Le prg met en oeuvre différents algorythm pour tenter de déterminer cette information:
    4.1 tente de récupérer cette information via le service musicbrainz au moyen du tag mbid fourni dans la réponse lastfm
    4.2 si le service musicbrainz ne permet pas de remonter l'information 


Dans l'immédiat tu n'essaies pas d'implémtenter d'autres features qui n'auraient pas été explicitement demandées dans ce prompt. Le cas échéant, tu demandes au developpeur s'il souhaite implémenter une feature qui te semble être particulièrement importante et non décrite dans ce prompt.