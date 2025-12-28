### contexte:

Nous souhaitons produire une application de proposition d'album basée sur les écoutes précédente. L'argorithme devra faire des propositions d'écoute basée sur les habitudes et les fréquences d'écoute des jours,semaines,mois précédents.

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
    4.2 si le service musicbrainz ne permet pas de remonter l'information un appel à l'API claude AI peut être envisagé.
5. le recours à l'API Claude AI engendre des frais et ne doit être utilisé que lorsque la qualité des informations récoltées n'est pas satisfaisante. Pour limiter les appels API payants le prog mettra en oeuvre les outils suivants:
    5.1 stockage dans une db sqlite interne au prg les informations pour les artistes déjà rencontrés lors d'exécution précédentes.
    5.2 le prg déterminera la qualité des information récoltées selon un algo à déterminer sous la forme d'un pourcentage (0 >= PRC <= 1 ) attribué à la qualité d'identification des écoutes traitées chaques écoutes est stockée dans la db sqlite.
    Les appals à Caude AI ne seront fait que si le score est inférieur à 0.8.
6. Les recommandations peuvent faire l'objet d'un appel à l'API Claude AI. Un maximum de 5 propositions sera fait par exécution.


Dans l'immédiat tu n'essaies pas d'implémtenter d'autres features qui n'auraient pas été explicitement demandées dans ce prompt. Le cas échéant, tu demandes au developpeur s'il souhaite implémenter une feature qui te semble être particulièrement importante et non décrite dans ce prompt.

### compléments:
ok j'ai besoin maintenant d'une série de EP REST qui soient dispo sur le 8098 et qui permettent de :

1. déclencher une màj des données via un appel à l'API last.fm (identique au main actuel)
2. d'intéroger le service pour qu'il me remontent les données enrichies sous la forme d'une collection d'objet dans un json.